local M = {}
local log = require 'ai-provider.log'

local providers = {
  copilot = require 'ai-provider.providers.copilot',
  ollama = require 'ai-provider.providers.ollama',
}

local state = {
  config = {
    providers = {},
  },
  model_cache = {},
  sources = {},
}

local function valid_source_id(source_id)
  return type(source_id) == 'string' and source_id ~= ''
end

local function model_display(provider, model)
  return provider .. '/' .. model
end

local function table_is_empty(value)
  if type(value) ~= 'table' then
    return true
  end
  return next(value) == nil
end

local function is_configured_provider(provider)
  return type(state.config.providers[provider]) == 'table'
end

local function source_name(source_id)
  local source = state.sources[source_id]
  if type(source) == 'table' and type(source.name) == 'string' and source.name ~= '' then
    return source.name
  end
  local prefs = M.load_preferences()
  source = prefs.sources and prefs.sources[source_id]
  if type(source) == 'table' and type(source.name) == 'string' and source.name ~= '' then
    return source.name
  end
  return source_id
end

local function source_registered_name(source_id)
  local source = state.sources[source_id]
  if type(source) == 'table' and type(source.name) == 'string' and source.name ~= '' then
    return source.name
  end
  local prefs = M.load_preferences()
  source = prefs.sources and prefs.sources[source_id]
  if type(source) == 'table' and type(source.name) == 'string' and source.name ~= '' then
    return source.name
  end
  return nil
end

local function source_display(source_id)
  return source_name(source_id)
end

local function has_source_model_preference(source_id)
  local prefs = M.load_preferences()
  local source = prefs.sources and prefs.sources[source_id]
  return type(source) == 'table'
    and is_configured_provider(source.provider)
    and type(source.model) == 'string'
    and source.model ~= ''
end

local function source_selection_display(source_id)
  local selection = M.get_source_selection(source_id)
  if not selection then
    return ''
  end

  if not has_source_model_preference(source_id) then
    return ' (default)'
  end

  local suffix = ' (' .. selection.label
  return suffix .. ')'
end

local function get_provider_config(provider)
  return state.config.providers[provider] or {}
end

local function validate_config(opts)
  if type(opts) ~= 'table' then
    error('ai-provider setup requires a config table', 3)
  end

  if type(opts.default_provider) ~= 'string' or opts.default_provider == '' then
    error('ai-provider setup requires default_provider', 3)
  end

  if type(opts.providers) ~= 'table' then
    error('ai-provider setup requires providers table', 3)
  end

  if not opts.providers[opts.default_provider] then
    error('ai-provider default_provider must be configured under providers: ' .. opts.default_provider, 3)
  end

  for provider, provider_config in pairs(opts.providers) do
    if not providers[provider] then
      error('ai-provider config references unknown provider: ' .. provider, 3)
    end
    if type(provider_config.default_model) ~= 'string' or provider_config.default_model == '' then
      error('ai-provider setup requires providers.' .. provider .. '.default_model', 3)
    end
    if provider_config.models ~= nil and type(provider_config.models) ~= 'table' then
      error('ai-provider providers.' .. provider .. '.models must be a table when set', 3)
    end
  end
end

local function preferences_file()
  return vim.fn.stdpath 'data' .. '/ai-provider-preferences.json'
end

function M.load_preferences()
  local file = io.open(preferences_file(), 'r')
  if not file then
    return {}
  end

  local content = file:read '*a'
  file:close()

  local ok, prefs = pcall(vim.json.decode, content)
  if ok and type(prefs) == 'table' then
    return prefs
  end
  return {}
end

function M.save_preferences(prefs)
  local file = io.open(preferences_file(), 'w')
  if not file then
    return false
  end

  file:write(vim.json.encode(prefs))
  file:close()
  return true
end

function M.get_provider(name)
  if not is_configured_provider(name) then
    return nil
  end
  return providers[name]
end

function M.get_provider_config(name)
  if not is_configured_provider(name) then
    return nil
  end
  return get_provider_config(name)
end

function M.list_providers()
  local names = {}
  for name in pairs(state.config.providers) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M.get_default_provider()
  local prefs = M.load_preferences()
  if type(prefs.default_provider) == 'string' and is_configured_provider(prefs.default_provider) then
    return prefs.default_provider
  end
  if type(state.config.default_provider) == 'string' and is_configured_provider(state.config.default_provider) then
    return state.config.default_provider
  end
  return nil
end

function M.set_default_provider(provider)
  if not is_configured_provider(provider) then
    return false
  end

  local prefs = M.load_preferences()
  prefs.default_provider = provider
  return M.save_preferences(prefs)
end

function M.get_selected_model(provider, source_id)
  local prefs = M.load_preferences()
  if valid_source_id(source_id) then
    local source = prefs.sources and prefs.sources[source_id]
    if type(source) == 'table'
      and source.provider == provider
      and type(source.model) == 'string'
      and source.model ~= ''
    then
      return source.model
    end
  end

  local provider_prefs = prefs[provider]
  if type(provider_prefs) == 'table' and type(provider_prefs.model) == 'string' and provider_prefs.model ~= '' then
    return provider_prefs.model
  end

  local provider_config = state.config.providers[provider]
  if type(provider_config) == 'table' and type(provider_config.default_model) == 'string' and provider_config.default_model ~= '' then
    return provider_config.default_model
  end

  return nil
end

function M.set_selected_model(provider, model)
  if not is_configured_provider(provider) then
    return false
  end

  local prefs = M.load_preferences()
  prefs[provider] = prefs[provider] or {}
  prefs[provider].model = model
  return M.save_preferences(prefs)
end

function M.get_source_selection(source_id)
  if not valid_source_id(source_id) then
    return nil
  end

  local prefs = M.load_preferences()
  local source = prefs.sources and prefs.sources[source_id]
  if type(source) == 'table' and is_configured_provider(source.provider) and type(source.model) == 'string' and source.model ~= '' then
    return { provider = source.provider, model = source.model, label = model_display(source.provider, source.model), name = source_registered_name(source_id) }
  end

  local provider = M.get_default_provider()
  local model = provider and M.get_selected_model(provider) or nil
  if provider and model then
    return { provider = provider, model = model, label = model_display(provider, model) }
  end

  return nil
end

function M.set_source_selection(source_id, provider, model)
  if not valid_source_id(source_id) or not is_configured_provider(provider) or type(model) ~= 'string' or model == '' then
    return false
  end

  local prefs = M.load_preferences()
  prefs.sources = prefs.sources or {}
  local source = type(prefs.sources[source_id]) == 'table' and prefs.sources[source_id] or {}
  source.provider = provider
  source.model = model
  source.label = nil
  source.name = nil
  prefs.sources[source_id] = source
  return M.save_preferences(prefs)
end

function M.register_source(source_id, opts)
  if not valid_source_id(source_id) then
    return false
  end

  opts = opts or {}
  state.sources[source_id] = state.sources[source_id] or {}
  state.sources[source_id].name = opts.name

  local prefs = M.load_preferences()
  prefs.sources = prefs.sources or {}
  local source = type(prefs.sources[source_id]) == 'table' and prefs.sources[source_id] or {}
  source.label = nil
  if type(opts.name) == 'string' and opts.name ~= '' then
    source.name = opts.name
  end

  if type(source.provider) == 'string' or type(source.model) == 'string' then
    prefs.sources[source_id] = source
    return M.save_preferences(prefs)
  end

  local provider = opts.provider
  local model = opts.model
  if provider and model and is_configured_provider(provider) then
    prefs.sources[source_id] = { provider = provider, model = model }
    if type(opts.name) == 'string' and opts.name ~= '' then
      prefs.sources[source_id].name = opts.name
    end
    return M.save_preferences(prefs)
  end

  if table_is_empty(source) then
    prefs.sources[source_id] = nil
  else
    prefs.sources[source_id] = source
  end
  if table_is_empty(prefs.sources) then
    prefs.sources = nil
  end
  return M.save_preferences(prefs)
end

function M.list_sources()
  local prefs = M.load_preferences()
  local sources = {}
  local seen = {}
  for source_id in pairs(prefs.sources or {}) do
    if type(source_id) == 'string' then
      seen[source_id] = true
      table.insert(sources, source_id)
    end
  end
  for source_id in pairs(state.sources) do
    if type(source_id) == 'string' and not seen[source_id] then
      table.insert(sources, source_id)
    end
  end
  table.sort(sources)
  return sources
end

function M.get_source_name(source_id)
  if not valid_source_id(source_id) then
    return nil
  end
  return source_name(source_id)
end

function M.check(provider, callback, opts)
  local implementation = M.get_provider(provider)
  if not implementation or not implementation.check then
    callback(false)
    return
  end
  implementation.check(callback, opts)
end

function M.auth(provider, callback, opts)
  local implementation = M.get_provider(provider)
  if not implementation or not implementation.auth then
    callback(false)
    return
  end
  implementation.auth(callback, opts)
end

function M.list_models(provider, callback, opts)
  local implementation = M.get_provider(provider)
  if not implementation or not implementation.list_models then
    callback(nil)
    return
  end
  opts = vim.tbl_extend('force', { provider_config = get_provider_config(provider) }, opts or {})
  implementation.list_models(function(models)
    if models then
      state.model_cache[provider] = models
    end
    callback(models)
  end, opts)
end

local function normalize_chat_args(first, second)
  if type(first) == 'string' and type(second) == 'table' and is_configured_provider(first) then
    local request = vim.tbl_extend('force', {}, second)
    request.provider = first
    return first, request
  end

  local request = first
  if type(request) == 'string' then
    request = { prompt = request, callback = second }
  elseif type(request) == 'table' then
    request = vim.tbl_extend('force', {}, request)
  else
    request = {}
  end

  local provider = request.provider or M.get_default_provider()
  if not provider then
    vim.notify('ai-provider is missing default_provider. Configure it in setup().', vim.log.levels.ERROR)
  end
  request.provider = provider
  return provider, request
end

function M.chat(first, second)
  local provider, request = normalize_chat_args(first, second)
  local implementation = M.get_provider(provider)
  if not implementation or not implementation.chat then
    log.error('chat requested unavailable provider: ' .. tostring(provider))
    if request.callback then
      request.callback(nil, nil)
    end
    return nil
  end

  request.model = request.model or M.get_selected_model(provider, request.source_id)
  request.provider_config = get_provider_config(provider)
  if not request.model then
    log.error(
      string.format('chat requested without selected model source=%s provider=%s', tostring(request.source_id), tostring(provider))
    )
    if request.callback then
      request.callback(nil, nil)
    end
    local source_hint = valid_source_id(request.source_id) and ('source ' .. request.source_id .. ' ') or provider .. ' '
    vim.notify('No model selected for ' .. source_hint .. '. Run :AIProvider source ' .. (request.source_id or '<id>') .. ' model first.', vim.log.levels.ERROR)
    return nil
  end

  if valid_source_id(request.source_id) then
    M.set_source_selection(request.source_id, provider, request.model)
  end

  log.info(
    string.format(
      'chat start source=%s provider=%s model=%s prompt_chars=%d max_tokens=%s context_size=%s stream=%s',
      tostring(request.source_id),
      provider,
      request.model,
      type(request.prompt) == 'string' and #request.prompt or 0,
      tostring(request.max_tokens),
      tostring(request.context_size),
      tostring(request.stream ~= false)
    )
  )
  return implementation.chat(request)
end

function M.chat_with(provider, request)
  return M.chat(provider, request)
end

local function collect_models(callback)
  local all = {}
  local provider_names = M.list_providers()
  local pending = #provider_names

  if pending == 0 then
    callback(all)
    return
  end

  for _, provider in ipairs(provider_names) do
    M.list_models(provider, function(models)
      for _, model in ipairs(models or {}) do
        table.insert(all, { provider = provider, model = model, label = model_display(provider, model) })
      end

      pending = pending - 1
      if pending == 0 then
        table.sort(all, function(a, b)
          return a.label < b.label
        end)
        callback(all)
      end
    end)
  end
end

function M.select_model(provider)
  if not provider then
    collect_models(function(models)
      if #models == 0 then
        vim.notify('No AI provider models are available.', vim.log.levels.WARN)
        return
      end

      local default_provider = M.get_default_provider()
      vim.ui.select(models, {
        prompt = 'Select AI model:',
        format_item = function(item)
          local current = item.provider == default_provider and item.model == M.get_selected_model(item.provider)
          local marker = current and '✓ ' or '  '
          return marker .. item.label
        end,
      }, function(choice)
        if not choice then
          return
        end
        M.set_default_provider(choice.provider)
        M.set_selected_model(choice.provider, choice.model)
        vim.notify('Default AI model set to ' .. choice.label, vim.log.levels.INFO)
      end)
    end)
    return
  end

  M.check(provider, function(working)
    if not working then
      vim.notify(provider .. ' is not reachable', vim.log.levels.ERROR)
      return
    end

    M.auth(provider, function(authenticated)
      if not authenticated then
        vim.notify(provider .. ' authentication failed', vim.log.levels.ERROR)
        return
      end

      M.list_models(provider, function(models)
        if not models or #models == 0 then
          vim.notify(provider .. ' is reachable but no models are available.', vim.log.levels.WARN)
          return
        end

        local current = M.get_selected_model(provider)
        vim.ui.select(models, {
          prompt = 'Select ' .. provider .. ' model:',
          format_item = function(model)
            local marker = model == current and '✓ ' or '  '
            return marker .. model
          end,
        }, function(choice)
          if not choice then
            return
          end
          M.set_selected_model(provider, choice)
          vim.notify(provider .. ' model set to ' .. choice, vim.log.levels.INFO)
        end)
      end)
    end)
  end, { force = true })
end

local function select_helper(opts, callback)
  if type(opts) == 'function' then
    callback = opts
    opts = {}
  end
  opts = opts or {}

  collect_models(function(models)
    if #models == 0 then
      vim.notify('No AI provider models are available.', vim.log.levels.WARN)
      if callback then
        callback(nil)
      end
      return
    end

    local current = opts.current or (valid_source_id(opts.source_id) and M.get_source_selection(opts.source_id) or nil)
    vim.ui.select(models, {
      prompt = opts.prompt or 'Select AI provider model:',
      format_item = function(item)
        local selected = current and item.provider == current.provider and item.model == current.model
        local marker = selected and '✓ ' or '  '
        return marker .. item.label
      end,
    }, function(choice)
      if not choice then
        if callback then
          callback(nil)
        end
        return
      end

      if callback then
        callback({ provider = choice.provider, model = choice.model, label = choice.label })
      end
    end)
  end)
end

function M.select_source_model(source_id)
  if valid_source_id(source_id) then
    select_helper({
      prompt = 'Select AI model for ' .. source_name(source_id) .. ':',
      source_id = source_id,
    }, function(choice)
      if not choice then
        return
      end
      M.set_source_selection(source_id, choice.provider, choice.model)
      vim.notify('AI model for ' .. source_name(source_id) .. ' set to ' .. choice.label, vim.log.levels.INFO)
    end)
    return
  end

  local sources = M.list_sources()
  if #sources == 0 then
    vim.notify('No AI provider sources have been seen yet.', vim.log.levels.WARN)
    return
  end

  vim.ui.select(sources, {
    prompt = 'Select model for Consumer:',
    format_item = function(item)
      return source_display(item) .. source_selection_display(item)
    end,
  }, function(choice)
    if choice then
      M.select_source_model(choice)
    end
  end)
end

local global_actions = { 'default', 'model', 'models', 'source', 'sources' }
local provider_actions = { 'auth', 'check', 'model', 'models' }

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function filter(values, prefix)
  local matches = {}
  for _, value in ipairs(values) do
    if starts_with(value, prefix) then
      table.insert(matches, value)
    end
  end
  return matches
end

function M.command_complete(arglead, cmdline)
  local parts = vim.split(cmdline, '%s+', { trimempty = true })
  if cmdline:match '%s$' then
    table.insert(parts, '')
  end

  local argc = math.max(#parts - 1, 0)
  if argc <= 1 then
    local first = vim.deepcopy(global_actions)
    vim.list_extend(first, M.list_providers())
    return filter(first, arglead)
  end

  local first_arg = parts[2]
  if first_arg == 'default' then
    return argc == 2 and filter(M.list_providers(), arglead) or {}
  end

  if first_arg == 'model' then
    if argc == 2 then
      local cached = {}
      for _, provider in ipairs(M.list_providers()) do
        for _, model in ipairs(state.model_cache[provider] or {}) do
          table.insert(cached, model_display(provider, model))
        end
      end
      table.sort(cached)
      return filter(cached, arglead)
    end
    return {}
  end

  if first_arg == 'models' then
    return {}
  end

  if first_arg == 'sources' then
    return {}
  end

  if first_arg == 'source' then
    if argc == 2 then
      return filter(M.list_sources(), arglead)
    end
    if argc == 3 then
      return filter({ 'model' }, arglead)
    end
    if parts[4] == 'model' then
      local cached = {}
      for _, provider in ipairs(M.list_providers()) do
        for _, model in ipairs(state.model_cache[provider] or {}) do
          table.insert(cached, model_display(provider, model))
        end
      end
      table.sort(cached)
      return filter(cached, arglead)
    end
    return {}
  end

  if not providers[first_arg] then
    return {}
  end

  if argc == 2 then
    return filter(provider_actions, arglead)
  end

  if parts[3] == 'model' then
    return filter(state.model_cache[first_arg] or {}, arglead)
  end

  return {}
end

local function print_lines(lines)
  vim.api.nvim_echo({ { table.concat(lines, '\n'), 'Normal' } }, true, {})
end

function M.run_command(args)
  if #args == 0 then
    M.select_model()
    return
  end

  if args[1] == 'model' then
    if args[2] then
      local provider, model = args[2]:match '^([^/]+)/(.+)$'
      if not provider or not model or not is_configured_provider(provider) then
        vim.notify('Expected model as provider/model, for example ollama/gemma4:e2b', vim.log.levels.ERROR)
        return
      end

      M.set_default_provider(provider)
      M.set_selected_model(provider, model)
      vim.notify('Default AI model set to ' .. model_display(provider, model), vim.log.levels.INFO)
    else
      M.select_model()
    end
    return
  end

  if args[1] == 'models' then
    collect_models(function(models)
      local lines = vim.tbl_map(function(item)
        return item.label
      end, models)
      print_lines(lines)
    end)
    return
  end

  if args[1] == 'sources' then
    local lines = vim.tbl_map(function(source_id)
      return source_display(source_id) .. source_selection_display(source_id)
    end, M.list_sources())
    print_lines(lines)
    return
  end

  if args[1] == 'source' then
    local source_id = args[2]
    if not valid_source_id(source_id) then
      vim.notify('Expected source ID, for example :AIProvider source ai-commit model', vim.log.levels.ERROR)
      return
    end

    local action = args[3] or 'model'
    if action ~= 'model' then
      vim.notify('Unknown AIProvider source action: ' .. action, vim.log.levels.ERROR)
      return
    end

    if args[4] then
      local provider, model = args[4]:match '^([^/]+)/(.+)$'
      if not provider or not model or not is_configured_provider(provider) then
        vim.notify('Expected source model as provider/model, for example ollama/gemma4:e2b', vim.log.levels.ERROR)
        return
      end
      M.set_source_selection(source_id, provider, model)
      vim.notify('AI model for ' .. source_id .. ' set to ' .. model_display(provider, model), vim.log.levels.INFO)
    else
      M.select_source_model(source_id)
    end
    return
  end

  if args[1] == 'default' then
    if args[2] then
      if M.set_default_provider(args[2]) then
        vim.notify('Default AI provider set to ' .. args[2], vim.log.levels.INFO)
      else
        vim.notify('Unknown AI provider: ' .. args[2], vim.log.levels.ERROR)
      end
      return
    end

    local provider = M.get_default_provider()
    local model = M.get_selected_model(provider)
    local suffix = model and (' (' .. model_display(provider, model) .. ')') or ''
    vim.notify('Default AI provider: ' .. provider .. suffix, vim.log.levels.INFO)
    return
  end

  local provider = args[1]
  if not is_configured_provider(provider) then
    vim.notify('Unknown AI provider: ' .. provider, vim.log.levels.ERROR)
    return
  end

  local action = args[2] or 'model'
  if action == 'check' then
    M.check(provider, function(working)
      vim.notify(provider .. ' working: ' .. tostring(working), working and vim.log.levels.INFO or vim.log.levels.ERROR)
    end, { force = true })
  elseif action == 'auth' then
    M.auth(provider, function(authenticated)
      vim.notify(provider .. ' authenticated: ' .. tostring(authenticated), authenticated and vim.log.levels.INFO or vim.log.levels.ERROR)
    end)
  elseif action == 'model' then
    if args[3] then
      M.set_selected_model(provider, args[3])
      vim.notify(provider .. ' model set to ' .. args[3], vim.log.levels.INFO)
    else
      M.select_model(provider)
    end
  elseif action == 'models' then
    M.list_models(provider, function(models)
      print_lines(models or {})
    end)
  else
    vim.notify('Unknown AIProvider action: ' .. action, vim.log.levels.ERROR)
  end
end

function M.setup(opts)
  validate_config(opts)
  state.config = vim.tbl_deep_extend('force', { providers = {} }, opts)

  vim.api.nvim_create_user_command('AIProvider', function(command)
    M.run_command(command.fargs)
  end, {
    nargs = '*',
    complete = M.command_complete,
    desc = 'Manage AI providers',
    force = true,
  })

  vim.defer_fn(function()
    for _, provider in ipairs(M.list_providers()) do
      M.list_models(provider, function() end)
    end
  end, 1000)
end

return M
