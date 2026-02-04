--- Model fetcher utility for fetching available models from various AI providers
--- @class ModelFetcherConfig
--- @field endpoint string API endpoint to fetch models from
--- @field api_key_env string Environment variable name containing the API key
--- @field cache_file string Path to cache file (optional, will be generated if not provided)
--- @field cache_ttl number Cache time-to-live in seconds (default: 24 hours)
--- @field transform_response fun(body: table): string[]? Function to transform API response to model list
--- @field headers table<string, string>? Additional headers to include in request
--- @field default_models string[]? Models to return if API call fails or no API key

local M = {}

--- Load models from cache synchronously
--- @param provider_name string Name of the provider
--- @param cache_ttl number? Cache TTL in seconds (default: 24 hours)
--- @return string[]? models Cached models or nil if not cached/expired
function M.load_cached_models(provider_name, cache_ttl)
  local json = vim.json
  local cache_file = vim.fn.stdpath 'cache' .. '/' .. provider_name .. '_models.json'
  cache_ttl = cache_ttl or (24 * 60 * 60)

  local f = io.open(cache_file, 'r')
  if not f then
    return nil
  end
  local content = f:read '*a'
  f:close()
  local ok, data = pcall(json.decode, content)
  if not ok or not data then
    return nil
  end

  -- Check if cache is expired
  if os.time() - (data.timestamp or 0) > cache_ttl then
    return nil
  end
  return data.models
end

--- @param provider_name string Name of the provider (used for logging and cache file naming)
--- @param config ModelFetcherConfig Configuration for the model fetcher
--- @param cb fun(models: string[]?) Callback function to receive the models
function M.fetch_models(provider_name, config, cb)
  local curl = require 'plenary.curl'
  local log = require('plenary.log').new { plugin = provider_name }
  local json = vim.json

  -- Set defaults
  local cache_ttl = config.cache_ttl or (24 * 60 * 60) -- 24 hours
  local cache_file = config.cache_file or (vim.fn.stdpath 'cache' .. '/' .. provider_name .. '_models.json')

  --- Load models from cache
  --- @return string[]?
  local function load_cache()
    local f = io.open(cache_file, 'r')
    if not f then
      return nil
    end
    local content = f:read '*a'
    f:close()
    local ok, data = pcall(json.decode, content)
    if not ok or not data then
      return nil
    end

    -- Check if cache is expired
    if os.time() - (data.timestamp or 0) > cache_ttl then
      log.debug('Cache expired for ' .. provider_name)
      return nil
    end
    return data.models
  end

  --- Save models to cache
  --- @param models string[]
  local function save_cache(models)
    local f = io.open(cache_file, 'w')
    if not f then
      log.warn('Failed to open cache file for writing: ' .. cache_file)
      return
    end
    local ok, encoded = pcall(json.encode, {
      timestamp = os.time(),
      models = models,
    })
    if not ok then
      log.warn 'Failed to encode cache data'
      f:close()
      return
    end
    f:write(encoded)
    f:close()
    log.debug('Cached models for ' .. provider_name)
  end

  -- Try loading from cache first
  local cached = load_cache()
  if cached then
    log.debug('Loading ' .. provider_name .. ' models from cache')
    cb(cached)
    return
  end

  -- Check if API key is set
  local api_key = os.getenv(config.api_key_env)
  if not api_key or api_key == '' then
    log.debug(config.api_key_env .. ' not set for ' .. provider_name)
    -- Return default models if provided
    cb(config.default_models)
    return
  end

  -- Build headers
  local headers = {
    ['Authorization'] = 'Bearer ' .. api_key,
    ['Content-Type'] = 'application/json',
  }

  -- Merge additional headers if provided
  if config.headers then
    for k, v in pairs(config.headers) do
      headers[k] = v
    end
  end

  -- Fetch models from API
  log.debug('Fetching models for ' .. provider_name .. ' from ' .. config.endpoint)
  curl.get(config.endpoint, {
    headers = headers,
    callback = function(res)
      if res.status ~= 200 then
        log.warn(string.format('Failed to fetch %s models: HTTP %d', provider_name, res.status))
        -- Fallback to default models
        vim.schedule(function()
          cb(config.default_models)
        end)
        return
      end

      local ok, body = pcall(json.decode, res.body)
      if not ok or not body then
        log.error(string.format('Error decoding %s response', provider_name))
        vim.schedule(function()
          cb(config.default_models)
        end)
        return
      end

      -- Transform the response to get model list
      local models = config.transform_response(body)

      if not models or #models == 0 then
        vim.schedule(function()
          local msg = string.format('No models found in %s response', provider_name)
          log.warn(msg)
          cb(config.default_models)
        end)
        return
      end

      log.debug(string.format('Loaded %d models from %s', #models, provider_name))
      save_cache(models)

      vim.schedule(function()
        cb(models)
      end)
    end,
  })
end

--- Inject models into avante provider configuration
--- @param provider_name string Name of the avante provider (e.g., 'openrouter', 'cerebro')
--- @param models string[]? List of models to inject
function M.inject_into_avante(provider_name, models)
  local log = require('plenary.log').new { plugin = 'model_fetcher' }

  if not models or #models == 0 then
    log.debug('No models to inject for ' .. provider_name)
    return
  end

  -- Check if avante is loaded
  local has_avante, avante_config = pcall(require, 'avante.config')
  if not has_avante then
    log.debug('Avante not loaded, skipping model injection for ' .. provider_name)
    return
  end

  -- Update the provider's model_names
  vim.schedule(function()
    if avante_config.providers and avante_config.providers[provider_name] then
      avante_config.providers[provider_name].model_names = models
      log.debug(string.format('Injected %d models into avante provider: %s', #models, provider_name))
    else
      log.debug(string.format('Avante provider "%s" not found in config', provider_name))
    end
  end)
end

--- Convenience function for OpenRouter
--- @param cb fun(models: string[]?)
function M.fetch_openrouter_models(cb)
  M.fetch_models('openrouter', {
    endpoint = 'https://openrouter.ai/api/v1/models',
    api_key_env = 'AVANTE_OPENROUTER_API_KEY',
    default_models = {
      'anthropic/claude-sonnet-4-20250514',
      'deepseek/deepseek-chat-v3.1',
      'x-ai/grok-code-fast-1',
      'qwen/qwen3-coder',
      'openai/gpt-4o',
      'google/gemini-2.5-flash-exp',
    },
    transform_response = function(body)
      if not body.data then
        return nil
      end
      local models = {}
      for _, m in ipairs(body.data) do
        table.insert(models, m.id)
      end
      return models
    end,
  }, function(models)
    M.inject_into_avante('openrouter', models)
    cb(models)
  end)
end

--- Convenience function for Cerebro
--- @param cb fun(models: string[]?)
function M.fetch_cerebro_models(cb)
  M.fetch_models('cerebro', {
    endpoint = 'https://chat.cerebroai.de/api/v1/models',
    api_key_env = 'AVANTE_CEREBRO_API_KEY',
    default_models = {
      'gemini-3-pro-preview',
      'gemini-2.5-flash',
      'gpt-5-chat-latest',
      'gpt-4o',
    },
    transform_response = function(body)
      if body.data then
        local models = {}
        for _, m in ipairs(body.data) do
          -- Handle both {id: "..."} and direct string formats
          local model_id = type(m) == 'string' and m or m.id
          if model_id then
            table.insert(models, model_id)
          end
        end
        return models
      elseif body.models then
        -- Alternative response format
        return body.models
      end
      return nil
    end,
  }, function(models)
    M.inject_into_avante('cerebro', models)
    cb(models)
  end)
end

return M
