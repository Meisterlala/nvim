local Job = require("plenary.job")
local Path = require("plenary.path")
local Log = require("plenary.log").new({
  plugin = "nvim-k8s-crd",
  level = "debug",
  use_console = false,
})

local M = {}

M.config = {
  cache_dir = vim.fn.expand("~/.cache/k8s-schemas/"),
  cache_ttl = 3600 * 24,
  k8s = {
    file_mask = "*.yaml",
  },
}

-- dir -> context name, persisted to cache_dir/dir-contexts.json
local dir_contexts = {}

local function dir_contexts_path()
  return Path:new(M.config.cache_dir, "dir-contexts.json")
end

local function load_dir_contexts()
  local p = dir_contexts_path()
  if p:exists() then
    local ok, decoded = pcall(vim.json.decode, p:read())
    if ok and type(decoded) == "table" then
      dir_contexts = decoded
    end
  end
end

local function save_dir_contexts()
  local p = dir_contexts_path()
  Path:new(M.config.cache_dir):mkdir({ parents = true })
  p:write(vim.json.encode(dir_contexts), "w")
end

local function kubectl_current_context()
  return vim.fn.system("kubectl config current-context"):gsub("%s+", "")
end

local function get_active_context()
  local cwd = vim.fn.getcwd()
  return dir_contexts[cwd] or kubectl_current_context()
end

local function all_json_path(context)
  return Path:new(M.config.cache_dir, context, "all.json")
end

local function apply_context(context)
  local schema_path = all_json_path(context)

  if not schema_path:exists() then
    vim.notify("[k8s-crd] No cached schemas for context '" .. context .. "'. Run :K8SSchemasGenerate", vim.log.levels.WARN)
  end

  if vim.lsp and vim.lsp.config then
    vim.lsp.config.yamlls = vim.lsp.config.yamlls or {
      cmd = { "yaml-language-server", "--stdio" },
      filetypes = { "yaml", "json" },
      settings = { yaml = { validate = true, schemaStore = { enable = false }, schemas = {} } },
    }
    vim.lsp.config.yamlls.settings.yaml.schemas = vim.tbl_extend(
      "force",
      vim.lsp.config.yamlls.settings.yaml.schemas,
      { [tostring(schema_path)] = M.config.k8s.file_mask }
    )

    for _, client in ipairs(vim.lsp.get_clients()) do
      if client.name == "yamlls" then
        vim.lsp.stop_client(client.id)
      end
    end

    vim.defer_fn(function()
      vim.lsp.enable({ "yamlls" })
    end, 100)
  else
    local lspconfig = require("lspconfig")
    lspconfig.yamlls.setup(vim.tbl_extend("force", lspconfig.yamlls.document_config.default_config, {
      settings = {
        yaml = {
          schemas = { [tostring(schema_path)] = M.config.k8s.file_mask },
        },
      },
    }))
  end
end

local function list_contexts(callback)
  Job:new({
    command = "kubectl",
    args = { "config", "get-contexts", "-o", "name" },
    on_exit = function(j, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("[k8s-crd] Failed to list kubectl contexts", vim.log.levels.ERROR)
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
  M.config = vim.tbl_extend("force", M.config, user_config or {})

  if vim.fn.executable("kubectl") ~= 1 then
    Log.info("kubectl not found. nvim-k8s-crd plugin will not run.")
    return
  end

  load_dir_contexts()

  local context = get_active_context()
  Log.debug("Active context: " .. context)

  if not all_json_path(context):exists() then
    M.generate_schemas()
  end

  M.config.k8s.file_mask = M.config.k8s.file_mask or "*.yaml"
  apply_context(context)

  vim.api.nvim_create_user_command("K8SSchemasGenerate", function()
    if vim.fn.executable("kubectl") ~= 1 then
      vim.notify("[k8s-crd] kubectl is missing.", vim.log.levels.ERROR)
      return
    end
    M.generate_schemas()
  end, { nargs = 0 })

  local function set_context(choice)
    local cwd = vim.fn.getcwd()
    dir_contexts[cwd] = choice
    save_dir_contexts()
    vim.notify("[k8s-crd] Context for " .. cwd .. " set to '" .. choice .. "'", vim.log.levels.INFO)
    apply_context(choice)
    if not all_json_path(choice):exists() then
      M.generate_schemas()
    end
  end

  vim.api.nvim_create_user_command("K8SSetContext", function(opts)
    local arg = opts.args ~= "" and opts.args or nil
    if arg then
      set_context(arg)
    else
      list_contexts(function(contexts)
        vim.ui.select(contexts, {
          prompt = "Select k8s context (current: " .. get_active_context() .. ")",
        }, function(choice)
          if choice then set_context(choice) end
        end)
      end)
    end
  end, {
    nargs = "?",
    complete = function()
      local result = vim.fn.system("kubectl config get-contexts -o name")
      return vim.split(vim.trim(result), "\n", { plain = true })
    end,
  })
end

function M.generate_schemas()
  local context = get_active_context()
  local schema_dir = Path:new(M.config.cache_dir, context)
  local all_file = schema_dir:joinpath("all.json")

  Path:new(schema_dir):mkdir({ parents = true })

  local fetch_openapi_job = Job:new({
    command = "kubectl",
    args = { "--context", context, "get", "--raw", "/openapi/v3" },
  })

  local all_types = {}
  local current_job = 0
  local total_jobs = 0

  local function fetch_schema(path, api, callback)
    path = path:gsub("/", "-")
    Job:new({
      command = "kubectl",
      args = { "--context", context, "get", "--raw", api.serverRelativeURL },
      on_exit = function(j, result_val)
        if result_val ~= 0 then
          Log.error("Error fetching OpenAPI: " .. api.serverRelativeURL, j:result())
          callback(false)
          return
        end

        local ok, schema = pcall(vim.json.decode, table.concat(j:result(), "\n"))
        if ok and schema.components and schema.components.schemas then
          local updated_schemas = { ["components"] = { ["schemas"] = schema.components.schemas } }

          for k, crd in pairs(schema.components.schemas) do
            if
              crd.type == "object"
              and crd.properties
              and crd.properties.apiVersion
              and crd.properties.kind
              and crd["x-kubernetes-group-version-kind"]
            then
              local kind_enum = {}
              local api_version_enum = {}
              for _, gvk in ipairs(crd["x-kubernetes-group-version-kind"]) do
                table.insert(kind_enum, gvk.kind)
                if gvk.group == "" then
                  table.insert(api_version_enum, gvk.version)
                else
                  table.insert(api_version_enum, gvk.group .. "/" .. gvk.version)
                end
              end
              crd.properties.kind.enum = kind_enum
              crd.properties.apiVersion.enum = api_version_enum
              table.insert(all_types, { ["$ref"] = path .. ".json#/components/schemas/" .. k })
            end
            updated_schemas.components.schemas[k] = crd
          end

          local schema_path = schema_dir:joinpath(path .. ".json")
          schema_path:write(vim.json.encode(updated_schemas), "w")
          Log.debug("Generated (" .. current_job .. "/" .. total_jobs .. "): " .. tostring(schema_path))
        end

        callback(true)
      end,
    }):start()
  end

  fetch_openapi_job:after(function()
    local result = fetch_openapi_job:result()
    local ok, schema_list = pcall(vim.json.decode, table.concat(result, "\n"))
    if not ok or not schema_list.paths then
      Log.error("Failed to parse OpenAPI path list")
      return
    end

    local paths = {}
    for path, api in pairs(schema_list.paths) do
      table.insert(paths, { path, api })
    end
    total_jobs = #paths

    local function run_next_schema(i)
      current_job = i

      if i > total_jobs then
        Path:new(all_file):write(vim.json.encode({ ["oneOf"] = all_types }), "w")
        Log.debug("Generated: " .. tostring(all_file))
        vim.schedule(function()
          vim.notify("[k8s-crd] Schemas generated for context '" .. context .. "'", vim.log.levels.INFO)
        end)
        return
      end

      local path_api = paths[i]
      fetch_schema(path_api[1], path_api[2], function(res)
        if res then
          run_next_schema(i + 1)
        else
          Log.debug("Retrying schema: " .. path_api[1])
          local timer = vim.loop.new_timer()
          timer:start(100, 0, vim.schedule_wrap(function()
            run_next_schema(i)
          end))
        end
      end)
    end

    run_next_schema(1)
  end)

  fetch_openapi_job:start()
end

return M
