local M = {}
local curl = require 'ai-provider.curl'

local DEFAULT_ENDPOINT = 'http://127.0.0.1:11434'
local HEALTH_CACHE_TTL = 30

local state = {
  health = nil,
  health_checked_at = 0,
}

local function endpoint()
  local configured = vim.g.ollama_endpoint or os.getenv 'OLLAMA_HOST'
  if configured and configured ~= '' then
    configured = configured:gsub('/+$', '')
    if not configured:match '^https?://' then
      configured = 'http://' .. configured
    end
    return configured
  end
  return DEFAULT_ENDPOINT
end

local function is_cancelled(request)
  return request and request.is_cancelled and request.is_cancelled()
end

local function configured_models(provider_config)
  local models = {}
  for name in pairs(provider_config.models or {}) do
    table.insert(models, name)
  end
  table.sort(models)
  return models
end

local function model_config(provider_config, model)
  local configured = provider_config.models and provider_config.models[model]
  if type(configured) == 'string' then
    return { model = configured }
  end
  if type(configured) == 'table' then
    return configured
  end
  return { model = model }
end

function M.check(callback, opts)
  opts = opts or {}
  local now = os.time()
  if not opts.force and state.health ~= nil and now - state.health_checked_at < HEALTH_CACHE_TTL then
    callback(state.health)
    return
  end

  curl.json {
    url = endpoint() .. '/api/tags',
    timeout = opts.timeout or 1000,
    callback = function(response)
      state.health = response.status == 200
      state.health_checked_at = os.time()
      callback(state.health)
    end,
  }
end

function M.auth(callback, opts)
  opts = opts or {}
  callback(true)
end

function M.list_models(callback, opts)
  opts = opts or {}
  local provider_config = opts.provider_config or {}
  curl.json {
    url = endpoint() .. '/api/tags',
    timeout = opts.timeout or 3000,
    callback = function(response)
      if response.status ~= 200 or type(response.json) ~= 'table' or type(response.json.models) ~= 'table' then
        callback(nil)
        return
      end

      local models = {}
      local seen = {}
      for _, model in ipairs(configured_models(provider_config)) do
        seen[model] = true
        table.insert(models, model)
      end

      for _, model in ipairs(response.json.models) do
        if type(model) == 'table' and type(model.name) == 'string' and not seen[model.name] then
          seen[model.name] = true
          table.insert(models, model.name)
        end
      end
      table.sort(models)
      callback(models)
    end,
  }
end

function M.chat(request)
  local started_at = vim.uv.hrtime()
  local chunks = {}
  local provider_config = request.provider_config or {}
  local selected_model = request.model
  local selected_config = model_config(provider_config, selected_model)
  local raw_model = selected_config.model or selected_model
  local context_size = request.context_size or selected_config.context_size or provider_config.context_size
  local keep_alive = request.keep_alive or provider_config.keep_alive
  local final_model = raw_model

  local body = {
    model = raw_model,
    messages = { { role = 'user', content = request.prompt } },
    stream = request.stream ~= false,
    options = {
      num_predict = request.max_tokens,
      num_ctx = context_size,
    },
    keep_alive = keep_alive,
  }

  local job = curl.stream_json_lines {
    url = endpoint() .. '/api/chat',
    body = body,
    timeout = request.timeout or 30000,
    is_cancelled = request.is_cancelled,
    on_json_line = function(data)
      if is_cancelled(request) then
        return
      end

      final_model = data.model or final_model
      local chunk = data.message and data.message.content or ''
      if chunk ~= '' then
        table.insert(chunks, chunk)
        if request.on_chunk then
          vim.schedule(function()
            request.on_chunk(chunk, data)
          end)
        end
      end
    end,
    callback = function(code)
      if is_cancelled(request) then
        return
      end

      if code ~= 0 then
        if request.callback then
          request.callback(nil, nil)
        end
        return
      end

      local elapsed_ms = (vim.uv.hrtime() - started_at) / 1e6
      if request.callback then
        request.callback(table.concat(chunks, ''), { requested_model = selected_model, used_model = final_model, elapsed_ms = elapsed_ms })
      end
    end,
  }

  if request.register_http_job then
    request.register_http_job(job)
  end
  return job
end

return M
