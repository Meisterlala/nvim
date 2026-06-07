local M = {}
local curl = require 'ai-provider.curl'
local log = require 'ai-provider.log'

local DEFAULT_ENDPOINT = 'http://127.0.0.1:11434'
local HEALTH_CACHE_TTL = 60
local MODEL_CACHE_TTL = 60
local STATUS_THROTTLE_MS = 100

local state = {
  health = nil,
  health_checked_at = 0,
  loaded_models = {},
  loaded_models_checked_at = 0,
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

local function elapsed_ms_since(started_at)
  return (vim.uv.hrtime() - started_at) / 1e6
end

local function tokens_per_second(count, duration_ns)
  if type(count) ~= 'number' or type(duration_ns) ~= 'number' or duration_ns < 1000000 then
    return nil
  end
  return count / (duration_ns / 1e9)
end

local function estimate_token_count(text)
  if type(text) ~= 'string' or text == '' then
    return 0
  end
  return math.max(1, math.floor((#text / 4) + 0.5))
end

local function canonical_model_name(model)
  if type(model) ~= 'string' then
    return nil
  end
  return model:match '^([^:]+:[^%s]+)' or model
end

local function cache_loaded_model(model)
  local name = canonical_model_name(model)
  if name then
    state.loaded_models[name] = true
    state.loaded_models_checked_at = os.time()
  end
end

local function cached_model_loaded(model)
  local name = canonical_model_name(model)
  if not name or os.time() - state.loaded_models_checked_at >= MODEL_CACHE_TTL then
    return nil
  end
  return state.loaded_models[name] == true
end

local function update_loaded_model_cache(models)
  state.loaded_models = {}
  for _, model in ipairs(models or {}) do
    local name = canonical_model_name(type(model) == 'table' and model.name or model)
    if name then
      state.loaded_models[name] = true
    end
  end
  state.loaded_models_checked_at = os.time()
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
      log.debug('ollama check status=' .. tostring(response.status) .. ' working=' .. tostring(state.health))
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
  local think = request.think
  if think == nil then
    think = selected_config.think
  end
  if think == nil then
    think = provider_config.think
  end
  local final_model = raw_model
  local done_reason = nil
  local provider_error = nil
  local metrics = {}
  local thinking_chars = 0
  local last_status_key = nil
  local last_status_phase = nil
  local last_status_sent_at = 0
  local status_throttle_ms = request.status_interval or STATUS_THROTTLE_MS
  local generation_started_at = nil
  local streamed_token_estimate = 0

  local function approximate_stream_tokens_per_second()
    if not generation_started_at or streamed_token_estimate == 0 then
      return nil
    end

    local elapsed_seconds = math.max((vim.uv.hrtime() - generation_started_at) / 1e9, 0.25)
    if elapsed_seconds <= 0 then
      return nil
    end

    return streamed_token_estimate / elapsed_seconds
  end

  local function emit_status(status)
    if not request.on_status then
      return
    end

    status.provider = 'ollama'
    status.model = status.model or selected_model
    status.used_model = status.used_model or final_model
    status.elapsed_ms = status.elapsed_ms or elapsed_ms_since(started_at)
    local key = table.concat({ status.phase or '', status.message or '', tostring(status.tokens_per_second), tostring(status.used_model) }, '|')
    if key == last_status_key then
      return
    end

    local now = vim.uv.hrtime()
    local phase = status.phase or ''
    local important = phase == 'loading' or phase == 'loaded' or phase == 'done' or phase == 'error' or phase ~= last_status_phase
    if not important and (now - last_status_sent_at) / 1e6 < status_throttle_ms then
      return
    end

    last_status_key = key
    last_status_phase = phase
    last_status_sent_at = now
    log.debug(
      string.format(
        'ollama status phase=%s model=%s tokens_per_second=%s elapsed_ms=%.0f',
        tostring(status.phase),
        tostring(status.model),
        status.tokens_per_second and string.format('%.2f', status.tokens_per_second) or 'nil',
        status.elapsed_ms
      )
    )
    vim.schedule(function()
      request.on_status(status)
    end)
  end

  log.info(
    string.format(
      'ollama request selected_model=%s raw_model=%s prompt_chars=%d context_size=%s max_tokens=%s keep_alive=%s timeout=%s stream=%s think=%s',
      tostring(selected_model),
      tostring(raw_model),
      type(request.prompt) == 'string' and #request.prompt or 0,
      tostring(context_size),
      tostring(request.max_tokens),
      tostring(keep_alive),
      tostring(request.timeout or 30000),
      tostring(request.stream ~= false),
      tostring(think)
    )
  )

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
  if think ~= nil then
    body.think = think
  end

  local function run_chat()
    return curl.stream_json_lines {
      url = endpoint() .. '/api/chat',
      body = body,
      timeout = request.timeout or 30000,
      is_cancelled = request.is_cancelled,
      on_json_line = function(data)
        if is_cancelled(request) then
          return
        end

        final_model = data.model or final_model
        done_reason = data.done_reason or done_reason
        if type(data.error) == 'string' and data.error ~= '' then
          provider_error = data.error
        end
        metrics.total_duration = data.total_duration or metrics.total_duration
        metrics.load_duration = data.load_duration or metrics.load_duration
        metrics.prompt_eval_count = data.prompt_eval_count or metrics.prompt_eval_count
        metrics.prompt_eval_duration = data.prompt_eval_duration or metrics.prompt_eval_duration
        metrics.eval_count = data.eval_count or metrics.eval_count
        metrics.eval_duration = data.eval_duration or metrics.eval_duration
        if data.model then
          cache_loaded_model(data.model)
        end
        local thinking = data.message and data.message.thinking or ''
        local chunk = data.message and data.message.content or ''
        if not generation_started_at and (thinking ~= '' or chunk ~= '') then
          generation_started_at = vim.uv.hrtime()
        end
        streamed_token_estimate = streamed_token_estimate + estimate_token_count(thinking) + estimate_token_count(chunk)
        local status_tokens_per_second = tokens_per_second(data.eval_count, data.eval_duration)
        if not status_tokens_per_second then
          status_tokens_per_second = approximate_stream_tokens_per_second()
        end
        if thinking ~= '' then
          thinking_chars = thinking_chars + #thinking
          emit_status {
            phase = 'thinking',
            message = 'Thinking',
            tokens_per_second = status_tokens_per_second,
          }
          if request.on_chunk then
            vim.schedule(function()
              request.on_chunk(thinking, data, 'thinking')
            end)
          end
        end
        if chunk ~= '' then
          table.insert(chunks, chunk)
          emit_status {
            phase = thinking_chars > 0 and 'generating' or 'generating',
            message = 'Generating response',
            tokens_per_second = status_tokens_per_second,
          }
          if request.on_chunk then
            vim.schedule(function()
              request.on_chunk(chunk, data, 'message')
            end)
          end
        end
      end,
      callback = function(code, error_message)
        if is_cancelled(request) then
          return
        end

        if code ~= 0 then
          log.error('ollama request process failed code=' .. tostring(code) .. ' model=' .. tostring(raw_model) .. ' error=' .. tostring(error_message))
          if request.callback then
            request.callback(nil, {
              requested_model = selected_model,
              used_model = final_model,
              elapsed_ms = (vim.uv.hrtime() - started_at) / 1e6,
              error = error_message or 'ollama request failed',
            })
          end
          emit_status {
            phase = 'error',
            message = error_message or 'Ollama request failed',
          }
          return
        end

        local elapsed_ms = (vim.uv.hrtime() - started_at) / 1e6
        local meta = vim.tbl_extend('force', {
          requested_model = selected_model,
          used_model = final_model,
          elapsed_ms = elapsed_ms,
          done_reason = done_reason,
        }, metrics)
        local message = table.concat(chunks, '')
        local prompt_tokens_per_second = tokens_per_second(metrics.prompt_eval_count, metrics.prompt_eval_duration)
        local eval_tokens_per_second = tokens_per_second(metrics.eval_count, metrics.eval_duration)
        log.info(
          string.format(
            'ollama response requested_model=%s used_model=%s done_reason=%s elapsed_ms=%.0f output_chars=%d context_size=%s max_tokens=%s load_ms=%s prompt_eval_count=%s prompt_eval_ms=%s prompt_tokens_per_second=%s eval_count=%s eval_ms=%s tokens_per_second=%s total_ms=%s',
            tostring(selected_model),
            tostring(final_model),
            tostring(done_reason),
            elapsed_ms,
            #message,
            tostring(context_size),
            tostring(request.max_tokens),
            metrics.load_duration and string.format('%.0f', metrics.load_duration / 1e6) or 'nil',
            tostring(metrics.prompt_eval_count),
            metrics.prompt_eval_duration and string.format('%.0f', metrics.prompt_eval_duration / 1e6) or 'nil',
            prompt_tokens_per_second and string.format('%.2f', prompt_tokens_per_second) or 'nil',
            tostring(metrics.eval_count),
            metrics.eval_duration and string.format('%.0f', metrics.eval_duration / 1e6) or 'nil',
            eval_tokens_per_second and string.format('%.2f', eval_tokens_per_second) or 'nil',
            metrics.total_duration and string.format('%.0f', metrics.total_duration / 1e6) or 'nil'
          )
        )
        if provider_error then
          meta.error = provider_error
          log.error('ollama provider error requested_model=' .. tostring(selected_model) .. ' error=' .. provider_error)
          if request.callback then
            request.callback(nil, meta)
          end
          emit_status {
            phase = 'error',
            message = provider_error,
            tokens = metrics.eval_count,
            tokens_per_second = tokens_per_second(metrics.eval_count, metrics.eval_duration),
          }
          return
        end
        if done_reason == 'length' then
          meta.error = 'ollama stopped because the context or generation length limit was reached'
          local error_prompt_tokens_per_second = tokens_per_second(metrics.prompt_eval_count, metrics.prompt_eval_duration)
          local error_eval_tokens_per_second = tokens_per_second(metrics.eval_count, metrics.eval_duration)
          log.error(
            string.format(
              'ollama length stop requested_model=%s used_model=%s prompt_chars=%d output_chars=%d context_size=%s max_tokens=%s load_ms=%s prompt_eval_count=%s prompt_eval_ms=%s prompt_tokens_per_second=%s eval_count=%s eval_ms=%s tokens_per_second=%s',
              tostring(selected_model),
              tostring(final_model),
              type(request.prompt) == 'string' and #request.prompt or 0,
              #message,
              tostring(context_size),
              tostring(request.max_tokens),
              metrics.load_duration and string.format('%.0f', metrics.load_duration / 1e6) or 'nil',
              tostring(metrics.prompt_eval_count),
              metrics.prompt_eval_duration and string.format('%.0f', metrics.prompt_eval_duration / 1e6) or 'nil',
              error_prompt_tokens_per_second and string.format('%.2f', error_prompt_tokens_per_second) or 'nil',
              tostring(metrics.eval_count),
              metrics.eval_duration and string.format('%.0f', metrics.eval_duration / 1e6) or 'nil',
              error_eval_tokens_per_second and string.format('%.2f', error_eval_tokens_per_second) or 'nil'
            )
          )
          if request.callback then
            request.callback(nil, meta)
          end
          emit_status {
            phase = 'error',
            message = meta.error,
            tokens = metrics.eval_count,
            tokens_per_second = error_eval_tokens_per_second,
          }
          return
        end

        if message == '' then
          meta.error = 'ollama returned no content'
          log.error('ollama returned no content requested_model=' .. tostring(selected_model) .. ' done_reason=' .. tostring(done_reason))
          if request.callback then
            request.callback(nil, meta)
          end
          emit_status {
            phase = 'error',
            message = meta.error,
            tokens = metrics.eval_count,
            tokens_per_second = tokens_per_second(metrics.eval_count, metrics.eval_duration),
          }
          return
        end

        emit_status {
          phase = 'done',
          message = 'Response complete',
          tokens = metrics.eval_count,
          tokens_per_second = eval_tokens_per_second,
        }
        if request.callback then
          request.callback(message, meta)
        end
      end,
    }
  end

  local job = nil
  local function start_chat(model_loaded)
    if model_loaded == true then
      emit_status {
        phase = 'loaded',
        message = 'Model loaded',
      }
    elseif model_loaded == false then
      emit_status {
        phase = 'loading',
        message = 'Loading model',
      }
    end

    emit_status {
      phase = 'context',
      message = 'Loading prompt context',
    }
    job = run_chat()
    if request.register_http_job then
      request.register_http_job(job)
    end
  end

  local cached_loaded = cached_model_loaded(raw_model)
  if cached_loaded ~= nil then
    start_chat(cached_loaded)
  elseif curl.json then
    job = curl.json {
      url = endpoint() .. '/api/ps',
      timeout = request.ps_timeout or provider_config.ps_timeout or 1000,
      callback = function(response)
        if is_cancelled(request) then
          return
        end

        local loaded = nil
        if response.status == 200 and type(response.json) == 'table' then
          update_loaded_model_cache(response.json.models)
          loaded = cached_model_loaded(raw_model)
        end
        start_chat(loaded)
      end,
    }
    if request.register_http_job then
      request.register_http_job(job)
    end
  else
    start_chat(nil)
  end
  return job
end

return M
