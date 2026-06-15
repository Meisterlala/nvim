local M = {}
local curl = require 'ai-provider.curl'
local log = require 'ai-provider.log'

local AUTH_URL = 'https://api.github.com/copilot_internal/v2/token'
local API_ENDPOINT = 'https://api.githubcopilot.com'
local AUTO_MODEL = 'auto'

local state = {
  api_token = nil,
  oauth_token = nil,
}

local function is_cancelled(request)
  return request and request.is_cancelled and request.is_cancelled()
end

local function format_body_for_log(body, max_len)
  if type(body) ~= 'string' then
    return '<no body>'
  end

  local compact = body:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if compact == '' then
    return '<empty body>'
  end

  local limit = max_len or 300
  if #compact <= limit then
    return compact
  end

  return compact:sub(1, limit) .. '...'
end

local function get_headers()
  local ok, avante_copilot = pcall(require, 'avante.providers.copilot')
  if ok and avante_copilot and avante_copilot.build_headers then
    local success, headers = pcall(avante_copilot.build_headers, avante_copilot)
    if success and headers then
      headers['Authorization'] = nil
      return headers
    end
  end

  return {
    ['User-Agent'] = 'GitHubCopilotChat/0.26.7',
    ['Editor-Version'] = 'vscode/1.105.1',
    ['Editor-Plugin-Version'] = 'copilot-chat/0.26.7',
    ['Copilot-Integration-Id'] = 'vscode-chat',
  }
end

local function get_config_dir()
  local xdg_config = vim.fn.expand '$XDG_CONFIG_HOME'
  if xdg_config and vim.fn.isdirectory(xdg_config) > 0 then
    return xdg_config
  end
  if vim.fn.has 'unix' == 1 then
    return vim.fn.expand '~/.config'
  end
  return vim.fn.expand '~/AppData/Local'
end

local function get_oauth_token()
  if state.oauth_token then
    return state.oauth_token
  end

  local Path = require 'plenary.path'
  local config_dir = get_config_dir()
  for _, filename in ipairs { 'hosts.json', 'apps.json' } do
    local token_path = Path:new(config_dir):joinpath('github-copilot', filename)
    if token_path:exists() then
      local ok, data = pcall(vim.json.decode, token_path:read())
      if ok then
        for key, value in pairs(data) do
          if key:match 'github.com' and value.oauth_token then
            state.oauth_token = value.oauth_token
            log.info('copilot oauth token found in ' .. filename)
            return state.oauth_token
          end
        end
      else
        log.warn('copilot failed to parse ' .. filename)
      end
    end
  end

  log.error 'copilot oauth token not found'
  return nil
end

local function register_job(request, job)
  if request and request.register_http_job and job then
    request.register_http_job(job)
  end
end

local function get_api_token(request, callback)
  if state.api_token and state.api_token.expires_at and state.api_token.expires_at > os.time() then
    callback(state.api_token.token)
    return
  end

  local oauth_token = get_oauth_token()
  if not oauth_token then
    callback(nil)
    return
  end

  local job = curl.json {
    url = AUTH_URL,
    headers = {
      ['Authorization'] = 'token ' .. oauth_token,
      ['Accept'] = 'application/json',
    },
    timeout = 5000,
    callback = function(response)
      if is_cancelled(request) then
        return
      end

      if response.status ~= 200 then
        log.error(string.format('copilot auth failed status=%s body=%s', tostring(response.status), format_body_for_log(response.body)))
        callback(nil)
        return
      end

      if type(response.json) ~= 'table' or not response.json.token or not response.json.expires_at then
        log.error('copilot auth response missing fields body=' .. format_body_for_log(response.body))
        callback(nil)
        return
      end

      state.api_token = response.json
      callback(state.api_token.token)
    end,
  }
  register_job(request, job)
end

function M.check(callback, opts)
  opts = opts or {}
  M.auth(callback, opts)
end

function M.auth(callback, opts)
  get_api_token(opts or {}, function(token)
    callback(token ~= nil)
  end)
end

function M.list_models(callback, _opts)
  local models = { AUTO_MODEL }
  local seen = { [AUTO_MODEL] = true }

  local ok, avante_copilot = pcall(require, 'avante.providers.copilot')
  if ok and avante_copilot and avante_copilot.list_models then
    local success, avante_models = pcall(avante_copilot.list_models, avante_copilot)
    if success and type(avante_models) == 'table' then
      for _, model in ipairs(avante_models) do
        local disabled = false
        if model.policy and type(model.policy) == 'table' then
          disabled = model.policy.state == 'disabled' or model.policy.state == 'unconfigured'
        elseif model.policy == false then
          disabled = true
        end

        local id = type(model) == 'table' and model.id or model
        if not disabled and type(id) == 'string' and id ~= '' and not seen[id] then
          seen[id] = true
          table.insert(models, id)
        end
      end
    end
  end

  for _, id in ipairs { 'gpt-4o-2024-11-20', 'gpt-4o-mini', 'gpt-4o' } do
    if not seen[id] then
      table.insert(models, id)
    end
  end

  callback(models)
end

function M.chat(request)
  local started_at = vim.uv.hrtime()

  local function emit_status(phase, message)
    if request.on_status then
      request.on_status {
        provider = 'copilot',
        phase = phase,
        message = message,
        model = request.model,
        elapsed_ms = (vim.uv.hrtime() - started_at) / 1e6,
      }
    end
  end

  emit_status('authenticating', 'Authenticating with Copilot')
  get_api_token(request, function(token)
    if is_cancelled(request) then
      return
    end

    if not token then
      if request.callback then
        request.callback(nil, {
          requested_model = request.model,
          used_model = request.model,
          elapsed_ms = (vim.uv.hrtime() - started_at) / 1e6,
          error = 'copilot authentication failed',
        })
      end
      return
    end

    local endpoint = (state.api_token.endpoints and state.api_token.endpoints.api) or API_ENDPOINT
    local headers = get_headers()
    headers['Authorization'] = 'Bearer ' .. token
    headers['Content-Type'] = 'application/json'

    local requested_model = request.model or AUTO_MODEL
    local active_job = nil

    local function send_chat(model, retried_auto)
      local body = {
        messages = { { role = 'user', content = request.prompt } },
        stream = false,
        max_tokens = request.max_tokens,
      }
      if model and model ~= AUTO_MODEL then
        body.model = model
      end

      emit_status('generating', 'Generating response')
      active_job = curl.json {
        method = 'POST',
        url = endpoint .. '/chat/completions',
        headers = headers,
        body = body,
        timeout = request.timeout or 30000,
        callback = function(response)
          if is_cancelled(request) then
            return
          end

          local elapsed_ms = (vim.uv.hrtime() - started_at) / 1e6
          if response.status ~= 200 then
            local error_code = response.json and response.json.error and response.json.error.code
            if response.status == 400 and error_code == 'unsupported_api_for_model' and body.model and not retried_auto then
              log.warn('copilot model unsupported by chat completions, retrying with auto: ' .. tostring(body.model))
              send_chat(AUTO_MODEL, true)
              return
            end

            local error_message = 'copilot api request failed: ' .. tostring(response.status)
            log.error(string.format('%s elapsed_ms=%.0f body=%s', error_message, elapsed_ms, format_body_for_log(response.body)))
            if request.callback then
              request.callback(nil, {
                requested_model = requested_model,
                used_model = model or AUTO_MODEL,
                elapsed_ms = elapsed_ms,
                error = error_message,
              })
            end
            return
          end

          local data = response.json
          local message = data and data.choices and data.choices[1] and data.choices[1].message and data.choices[1].message.content
          if type(message) ~= 'string' or message == '' then
            log.error('copilot response missing message body=' .. format_body_for_log(response.body))
            if request.callback then
              request.callback(nil, {
                requested_model = requested_model,
                used_model = model or AUTO_MODEL,
                elapsed_ms = elapsed_ms,
                error = 'copilot returned no content',
              })
            end
            return
          end

          local used_model = data.model or body.model or AUTO_MODEL
          log.info(string.format('copilot response requested_model=%s used_model=%s elapsed_ms=%.0f', requested_model, used_model, elapsed_ms))
          emit_status('done', 'Response complete')
          if request.callback then
            request.callback(message, {
              requested_model = requested_model,
              used_model = used_model,
              elapsed_ms = elapsed_ms,
            })
          end
        end,
      }
      register_job(request, active_job)
    end

    send_chat(request.model or AUTO_MODEL, false)
    return active_job
  end)
end

return M
