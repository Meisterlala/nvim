local Job = require 'plenary.job'
local Path = require 'plenary.path'
local Log = require('plenary.log').new {
  plugin = 'nvim-k8s-crd',
  level = 'debug',
  use_console = false,
}

local M = {}

-- kustomization.yaml is already mapped to the SchemaStore kustomize schema in
-- lsp/yamlls.lua (kustomize.config.k8s.io is client-side-only and never shows
-- up in a cluster's OpenAPI, so it can't be fetched like the CRDs below).
-- We only need to make sure our own CRD-derived schema never also matches
-- that file, since yaml-language-server ANDs together every schema entry
-- that matches a given file.
local KUSTOMIZE_FILE_GLOB = '**/kustomization.yaml'

M.config = {
  cache_dir = vim.fn.expand '~/.cache/k8s-schemas/',
  cache_ttl = 3600 * 24,
  download_concurrency = 8,
  k8s = {
    file_mask = '*.yaml',
  },
}

-- dir -> context name, persisted to cache_dir/dir-contexts.json
local dir_contexts = {}

local function dir_contexts_path()
  return Path:new(M.config.cache_dir, 'dir-contexts.json')
end

local function load_dir_contexts()
  local p = dir_contexts_path()
  if p:exists() then
    local ok, decoded = pcall(vim.json.decode, p:read())
    if ok and type(decoded) == 'table' then
      dir_contexts = decoded
    end
  end
end

local function save_dir_contexts()
  local p = dir_contexts_path()
  Path:new(M.config.cache_dir):mkdir { parents = true }
  p:write(vim.json.encode(dir_contexts), 'w')
end

local function unwrap_description(text)
  local paragraphs = {}
  for para in (text .. '\n\n'):gmatch '(.-)\n\n' do
    table.insert(paragraphs, (para:gsub('\n', ' ')))
  end
  return table.concat(paragraphs, '\n\n')
end

local function fix_descriptions(node)
  if type(node) ~= 'table' then
    return
  end
  if type(node.description) == 'string' then
    node.description = unwrap_description(node.description)
  end
  for _, v in pairs(node) do
    if type(v) == 'table' then
      fix_descriptions(v)
    end
  end
end

local function kubectl_current_context()
  return vim.fn.system('kubectl config current-context'):gsub('%s+', '')
end

local function get_active_context()
  local cwd = vim.fn.getcwd()
  return dir_contexts[cwd] or kubectl_current_context()
end

local function all_json_filename(context)
  return 'k8s-' .. context .. '.json'
end

local function all_json_path(context)
  return Path:new(M.config.cache_dir, context, all_json_filename(context))
end

local function crd_file_mask()
  local mask = M.config.k8s.file_mask
  local globs = type(mask) == 'table' and vim.deepcopy(mask) or { mask }
  table.insert(globs, '!' .. KUSTOMIZE_FILE_GLOB)
  return globs
end

-- Avoid warning on every yaml file (e.g. huge, unrelated ones) by only
-- flagging buffers that actually look like a k8s manifest and are cheap to scan.
local function current_buffer_looks_like_k8s_manifest()
  local bufnr = vim.api.nvim_get_current_buf()
  local size = vim.api.nvim_buf_get_offset(bufnr, vim.api.nvim_buf_line_count(bufnr))
  if size < 0 or size > 500 * 1024 then
    return false
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  return text:find('apiVersion:', 1, true) ~= nil and text:find('kind:', 1, true) ~= nil
end

local function apply_context(context)
  local schema_path = all_json_path(context)
  local schema_exists = schema_path:exists()

  if not schema_exists and current_buffer_looks_like_k8s_manifest() then
    vim.notify("No cached schemas for context '" .. context .. "'. Run :K8SSchemasGenerate", vim.log.levels.WARN)
  end

  -- Only tell yamlls about our schema once it actually exists on disk;
  -- pointing it at a not-yet-generated file makes it fail with "No content".
  local schemas = {}
  if schema_exists then
    schemas[vim.uri_from_fname(tostring(schema_path))] = crd_file_mask()
  end

  if vim.lsp and vim.lsp.config then
    -- `vim.lsp.config.yamlls.x = y` only mutates a freshly recomputed
    -- snapshot returned by __index and silently fails to persist; the
    -- function-call form is the only one that actually writes into
    -- Neovim's config store.
    vim.lsp.config('yamlls', {
      settings = { yaml = { validate = true, schemaStore = { enable = false }, schemas = schemas } },
    })

    -- Config changes only apply to newly-started clients, so push them live
    -- to any already-running yamlls client too. This avoids restarting the
    -- client altogether (stop() is async, so a restart risks racing with a
    -- still-tearing-down client and leaving buffers unattached).
    local clients = vim.lsp.get_clients { name = 'yamlls' }
    if #clients > 0 then
      for _, client in ipairs(clients) do
        client.settings = client.settings or {}
        client.settings.yaml = client.settings.yaml or {}
        -- Merge into the schemas the client already resolved (e.g. the
        -- kustomize/for_k8s entries from lsp/yamlls.lua) instead of
        -- replacing the table outright, which would otherwise drop them.
        client.settings.yaml.schemas = vim.tbl_extend('force', client.settings.yaml.schemas or {}, schemas)
        client:notify('workspace/didChangeConfiguration', { settings = client.settings })
      end
    else
      vim.lsp.enable 'yamlls'
    end
  else
    local lspconfig = require 'lspconfig'
    lspconfig.yamlls.setup(vim.tbl_extend('force', lspconfig.yamlls.document_config.default_config, {
      settings = {
        yaml = {
          schemas = schemas,
        },
      },
    }))
  end
end

local function list_contexts(callback)
  Job:new({
    command = 'kubectl',
    args = { 'config', 'get-contexts', '-o', 'name' },
    on_exit = function(j, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify('Failed to list kubectl contexts', vim.log.levels.ERROR)
        end)
        return
      end
      vim.schedule(function()
        callback(j:result())
      end)
    end,
  }):start()
end

function M.setup(user_config)
  M.config = vim.tbl_extend('force', M.config, user_config or {})

  if vim.fn.executable 'kubectl' ~= 1 then
    Log.info 'kubectl not found. nvim-k8s-crd plugin will not run.'
    return
  end

  load_dir_contexts()

  local context = get_active_context()
  Log.debug('Active context: ' .. context)

  M.config.k8s.file_mask = M.config.k8s.file_mask or '*.yaml'
  apply_context(context)

  vim.api.nvim_create_user_command('K8SSchemasGenerate', function()
    if vim.fn.executable 'kubectl' ~= 1 then
      vim.notify('kubectl is missing.', vim.log.levels.ERROR)
      return
    end
    M.generate_schemas()
  end, { nargs = 0 })

  local function set_context(choice)
    local cwd = vim.fn.getcwd()
    dir_contexts[cwd] = choice
    save_dir_contexts()
    vim.notify('Context for ' .. cwd .. " set to '" .. choice .. "'", vim.log.levels.INFO)
    apply_context(choice)
  end

  vim.api.nvim_create_user_command('K8SSetContext', function(opts)
    local arg = opts.args ~= '' and opts.args or nil
    if arg then
      set_context(arg)
    else
      list_contexts(function(contexts)
        vim.ui.select(contexts, {
          prompt = 'Select k8s context (current: ' .. get_active_context() .. ')',
        }, function(choice)
          if choice then
            set_context(choice)
          end
        end)
      end)
    end
  end, {
    nargs = '?',
    complete = function()
      local result = vim.fn.system 'kubectl config get-contexts -o name'
      return vim.split(vim.trim(result), '\n', { plain = true })
    end,
  })
end

function M.generate_schemas()
  local context = get_active_context()
  local schema_dir = Path:new(M.config.cache_dir, context)
  local all_file = schema_dir:joinpath(all_json_filename(context))

  Path:new(schema_dir):mkdir { parents = true }

  local ok_fidget, fidget_progress = pcall(require, 'fidget.progress')
  local progress = ok_fidget
      and fidget_progress.handle.create {
        title = 'k8s-crd',
        message = "Fetching Schemas from '" .. context .. "'",
        lsp_client = { name = 'k8s-crd' },
        percentage = 0,
      }
    or nil

  local fetch_openapi_job = Job:new {
    command = 'kubectl',
    args = { '--context', context, 'get', '--raw', '/openapi/v3' },
  }

  local all_types = {}
  local seen_types = {}
  local current_job = 0
  local total_jobs = 0

  local function fetch_schema(path, api, callback)
    path = path:gsub('/', '-')
    Job:new({
      command = 'kubectl',
      args = { '--context', context, 'get', '--raw', api.serverRelativeURL },
      on_exit = function(j, result_val)
        if result_val ~= 0 then
          Log.error('Error fetching OpenAPI: ' .. api.serverRelativeURL, j:result())
          callback(false)
          return
        end

        local ok, schema = pcall(vim.json.decode, table.concat(j:result(), '\n'))
        if ok and schema.components and schema.components.schemas then
          fix_descriptions(schema.components.schemas)
          local updated_schemas = { ['components'] = { ['schemas'] = schema.components.schemas } }

          for k, crd in pairs(schema.components.schemas) do
            if crd.type == 'object' and crd.properties and crd.properties.apiVersion and crd.properties.kind and crd['x-kubernetes-group-version-kind'] then
              local kind_enum = {}
              local api_version_enum = {}
              for _, gvk in ipairs(crd['x-kubernetes-group-version-kind']) do
                table.insert(kind_enum, gvk.kind)
                if gvk.group == '' then
                  table.insert(api_version_enum, gvk.version)
                else
                  table.insert(api_version_enum, gvk.group .. '/' .. gvk.version)
                end
              end
              crd.properties.kind.enum = kind_enum
              crd.properties.apiVersion.enum = api_version_enum
              if not seen_types[k] then
                seen_types[k] = true
                table.insert(all_types, { ['$ref'] = path .. '.json#/components/schemas/' .. k })
              end
            end
            updated_schemas.components.schemas[k] = crd
          end

          local schema_path = schema_dir:joinpath(path .. '.json')
          schema_path:write(vim.json.encode(updated_schemas), 'w')
          Log.debug('Generated (' .. current_job .. '/' .. total_jobs .. '): ' .. tostring(schema_path))
        end

        callback(true)
      end,
    }):start()
  end

  fetch_openapi_job:after(function()
    local result = fetch_openapi_job:result()
    local ok, schema_list = pcall(vim.json.decode, table.concat(result, '\n'))
    if not ok or not schema_list.paths then
      Log.error 'Failed to parse OpenAPI path list'
      if progress then
        vim.schedule(function()
          progress:report { message = 'Failed to parse OpenAPI schema list' }
          progress:cancel()
        end)
      end
      return
    end

    local paths = {}
    for path, api in pairs(schema_list.paths) do
      table.insert(paths, { path, api })
    end
    total_jobs = #paths

    local next_index = 1
    local active_workers = math.min(M.config.download_concurrency, total_jobs)
    local finished_workers = 0

    local function finish()
      Path:new(all_file):write(vim.json.encode { ['oneOf'] = all_types }, 'w')
      Log.debug('Generated: ' .. tostring(all_file))
      if progress then
        vim.schedule(function()
          progress:finish()
        end)
      end
      vim.schedule(function()
        vim.notify("Schemas generated for context '" .. context .. "'", vim.log.levels.INFO)
        apply_context(context)
      end)
    end

    if active_workers == 0 then
      finish()
      return
    end

    -- Retries the same item (rather than advancing) until it succeeds.
    local function fetch_with_retry(path_api, callback)
      fetch_schema(path_api[1], path_api[2], function(res)
        if res then
          callback()
        else
          Log.debug('Retrying schema: ' .. path_api[1])
          local timer = vim.loop.new_timer()
          timer:start(
            100,
            0,
            vim.schedule_wrap(function()
              fetch_with_retry(path_api, callback)
            end)
          )
        end
      end)
    end

    local function worker()
      local idx = next_index
      next_index = next_index + 1
      if idx > total_jobs then
        finished_workers = finished_workers + 1
        if finished_workers == active_workers then
          finish()
        end
        return
      end

      fetch_with_retry(paths[idx], function()
        current_job = current_job + 1
        if progress then
          -- fidget's report() calls vim.fn.mode() internally, which isn't
          -- allowed from the fast-event context plenary.job callbacks run in.
          local done = current_job
          vim.schedule(function()
            progress:report {
              message = 'Downloading Schemas',
              percentage = math.floor(done / total_jobs * 100),
            }
          end)
        end
        worker()
      end)
    end

    -- `download_concurrency` workers each pull the next item off the shared
    -- queue as soon as they're free, instead of fetching all ~150 schemas
    -- one at a time.
    for _ = 1, active_workers do
      worker()
    end
  end)

  fetch_openapi_job:start()
end

return M
