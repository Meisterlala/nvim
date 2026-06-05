local M = {}
local log = require 'ai-provider.log'

local providers = {
  ollama = require 'ai-provider.providers.ollama',
}

local state = {
  config = {
    providers = {},
  },
  model_cache = {},
}

local function is_configured_provider(provider)
  return type(state.config.providers[provider]) == 'table'
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

function M.get_provider_implementation(name)
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

function M.get_selected_model(provider)
  local prefs = M.load_preferences()
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

  request.model = request.model or M.get_selected_model(provider)
  request.provider_config = get_provider_config(provider)
  if not request.model then
    log.error('chat requested without selected model for provider: ' .. tostring(provider))
    if request.callback then
      request.callback(nil, nil)
    end
    vim.notify('No model selected for ' .. provider .. '. Run :AIProvider ' .. provider .. ' model first.', vim.log.levels.ERROR)
    return nil
  end

  log.info(
    string.format(
      'chat start provider=%s model=%s prompt_chars=%d max_tokens=%s context_size=%s stream=%s',
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

local function model_display(provider, model)
  return provider .. '/' .. model
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

function M.select_helper(opts, callback)
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

    local current = opts.current
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

local global_actions = { 'default', 'model', 'models' }
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
