local config = require 'ai-commit.config'
local log = require('ai-commit.log').get
local prompts = require 'ai-commit.prompts'
local util = require 'ai-commit.util'

local M = {}

local function dump_prompt(prompt)
  if config.values.log_level ~= 'debug' then
    return
  end

  local path = config.values.prompt_dump_path
  if type(path) ~= 'string' or path == '' then
    return
  end

  local logger = log()
  local ok, err = pcall(function()
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    vim.fn.writefile(vim.split(prompt, '\n', { plain = true }), path)
  end)

  if ok then
    logger.debug('Commit prompt dumped to ' .. path)
  else
    logger.warn('Failed to dump commit prompt to ' .. path .. ': ' .. tostring(err))
  end
end

local function child_request_context(request_context, overrides)
  return vim.tbl_extend('force', request_context or {}, overrides or {})
end

---@return string
function M.selected_model_name()
  local values = config.values
  local provider_prefix = ''
  if values.provider == 'ollama' then
    provider_prefix = '[Ollama] '
  elseif values.provider == 'openrouter' then
    provider_prefix = '[OpenRouter] '
  elseif values.provider == 'copilot' and values.model then
    provider_prefix = '[Copilot] '
  end

  if type(values.model_name) == 'string' and values.model_name ~= '' then
    return provider_prefix .. values.model_name
  end
  if type(values.model) == 'string' and values.model ~= '' then
    return provider_prefix .. values.model
  end
  if values.provider == 'copilot' then
    return 'Copilot default'
  end
  return 'Unknown'
end

function M.select_model()
  local logger = log()
  local ai_provider = require 'ai-provider'
  logger.info('Opening AI provider model picker for source=' .. config.message_source_id)
  ai_provider.select_source_model(config.message_source_id)
end

function M.select_summary_model()
  local logger = log()
  local ai_provider = require 'ai-provider'
  logger.info('Opening AI provider model picker for source=' .. config.summary_source_id)
  ai_provider.select_source_model(config.summary_source_id)
end

---@param full_prompt string
---@param callback function(string|nil, table|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
local function complete_ai_provider(source_id, full_prompt, callback, status_callback, request_context)
  local logger = log()
  local ai_provider = require 'ai-provider'
  local selection = ai_provider.get_source_selection(source_id)
  local provider = selection and selection.provider or ai_provider.get_default_provider() or 'ollama'
  local model = selection and selection.model or ai_provider.get_selected_model(provider, source_id)

  if not model then
    logger.error('No AI provider model selected for source=' .. source_id .. ' provider=' .. provider)
    vim.notify('No AI model selected. Run :AIProvider source ' .. source_id .. ' model first.', vim.log.levels.ERROR)
    callback(nil, nil)
    return
  end

  if status_callback then
    local action = request_context and request_context.status_action
    status_callback(action and (action .. ' with ' .. model) or ('Waiting for response from ' .. model))
  end

  local function report_provider_status(status)
    if not status_callback or type(status) ~= 'table' then
      return
    end
    local status_model = status.model or model
    local action = request_context and request_context.status_action
    if status.phase == 'loading' then
      status_callback(action and (action .. ' with ' .. status_model) or ('Loading model ' .. status_model))
    elseif status.phase == 'loaded' then
      status_callback('Loaded model ' .. status_model)
    elseif status.phase == 'thinking' then
      local suffix = status.tokens_per_second and string.format(' (%.1f t/s)', status.tokens_per_second) or ''
      status_callback((action or 'Thinking') .. ' with ' .. status_model .. suffix)
    elseif status.phase == 'generating' then
      local suffix = status.tokens_per_second and string.format(' (%.1f t/s)', status.tokens_per_second) or ''
      status_callback((action or 'Generating response') .. ' with ' .. status_model .. suffix)
    elseif status.phase == 'error' then
      status_callback('Provider error from ' .. status_model)
    end
  end

  ai_provider.chat(provider, {
    source_id = source_id,
    model = model,
    prompt = full_prompt,
    stream = true,
    preload = true,
    max_tokens = config.values.max_tokens,
    is_cancelled = request_context and request_context.is_cancelled,
    register_http_job = request_context and request_context.register_http_job,
    on_status = report_provider_status,
    on_chunk = request_context and request_context.on_chunk,
    status_interval = config.values.spinner_interval,
    callback = function(message, meta)
      if request_context and request_context.is_cancelled and request_context.is_cancelled() then
        return
      end
      if not message then
        logger.error(provider .. ' chat request failed: ' .. tostring(meta and meta.error or 'unknown error'))
        vim.notify(provider .. ' request failed. See ai-commit logs.', vim.log.levels.ERROR)
        callback(nil, nil)
        return
      end
      callback(util.clean_message(message), { requested_model = model, used_model = meta and meta.used_model or model })
    end,
  })
end

---@param full_prompt string
---@param callback function(string|nil, table|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
local function complete_copilot(source_id, full_prompt, callback, status_callback, request_context)
  local logger = log()
  local ai_provider = require 'ai-provider'
  local model = config.values.model or ai_provider.get_selected_model('copilot', source_id) or 'auto'

  if status_callback then
    status_callback('Waiting for response from ' .. model)
  end

  ai_provider.chat('copilot', {
    model = model,
    prompt = full_prompt,
    stream = false,
    max_tokens = config.values.max_tokens,
    timeout = config.values.chat_timeout,
    is_cancelled = request_context and request_context.is_cancelled,
    register_http_job = request_context and request_context.register_http_job,
    on_status = function(status)
      if not status_callback or type(status) ~= 'table' then
        return
      end
      if status.phase == 'authenticating' then
        status_callback 'Authenticating with Copilot'
      elseif status.phase == 'generating' then
        status_callback('Generating response with ' .. (status.model or model))
      elseif status.phase == 'error' then
        status_callback 'Provider error from Copilot'
      end
    end,
    callback = function(message, meta)
      if request_context and request_context.is_cancelled and request_context.is_cancelled() then
        return
      end
      if not message then
        logger.error('Copilot chat request failed through ai-provider: ' .. tostring(meta and meta.error or 'unknown error'))
        vim.notify('Copilot request failed. See ai-commit logs.', vim.log.levels.ERROR)
        callback(nil, nil)
        return
      end
      callback(util.clean_message(message), { requested_model = model, used_model = meta and meta.used_model or model })
    end,
  })
end

---@param full_prompt string
---@param callback function(string|nil, table|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
local function complete_openrouter(source_id, full_prompt, callback, status_callback, request_context)
  local logger = log()
  local api_key = os.getenv 'AVANTE_OPENROUTER_API_KEY' or os.getenv 'OPENROUTER_API_KEY'
  if not api_key then
    logger.error 'OpenRouter API key not found'
    vim.notify('OpenRouter API key not found. Please set AVANTE_OPENROUTER_API_KEY or OPENROUTER_API_KEY.', vim.log.levels.ERROR)
    callback(nil, nil)
    return
  end

  local model = config.values.model or 'anthropic/claude-sonnet-4-20250514'
  if status_callback then
    status_callback('Waiting for response from ' .. model)
  end

  local curl = require 'plenary.curl'
  local job = curl.post(config.values.openrouter.endpoint .. '/chat/completions', {
    headers = {
      ['Authorization'] = 'Bearer ' .. api_key,
      ['Content-Type'] = 'application/json',
      ['HTTP-Referer'] = 'https://github.com/opencode-sh/ai-commit',
      ['X-Title'] = 'ai-commit.lua',
    },
    body = vim.json.encode {
      messages = { { role = 'user', content = full_prompt } },
      stream = false,
      max_tokens = config.values.max_tokens,
      model = model,
      include_reasoning = config.values.openrouter.reasoning,
    },
    timeout = config.values.chat_timeout,
    callback = vim.schedule_wrap(function(response)
      if request_context and request_context.is_cancelled and request_context.is_cancelled() then
        return
      end
      if response.status ~= 200 then
        logger.error(string.format('OpenRouter API error: %d body=%s', response.status, util.format_body_for_log(response.body)))
        vim.notify('OpenRouter API request failed (' .. response.status .. '). See ai-commit logs.', vim.log.levels.ERROR)
        callback(nil, nil)
        return
      end

      local ok, data = pcall(vim.json.decode, response.body)
      local message_obj = ok and data.choices and data.choices[1] and data.choices[1].message
      if not message_obj then
        logger.error('Failed to parse OpenRouter response body=' .. util.format_body_for_log(response.body))
        callback(nil, nil)
        return
      end

      local content = message_obj.content or ''
      if (content == '' or content:match '^%s*$') and message_obj.reasoning then
        content = message_obj.reasoning
      end
      callback(util.clean_message(content), { requested_model = model, used_model = data.model or model })
    end),
    on_error = vim.schedule_wrap(function(err)
      if request_context and request_context.is_cancelled and request_context.is_cancelled() then
        return
      end
      logger.error('OpenRouter chat request failed: ' .. tostring(err and err.stderr or 'unknown error'))
      callback(nil, nil)
    end),
  })

  if request_context and request_context.register_http_job then
    request_context.register_http_job(job)
  end
end

---@param full_prompt string
---@param callback function(string|nil, table|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
function M.complete_prompt(full_prompt, callback, status_callback, request_context)
  local logger = log()
  local ai_provider = require 'ai-provider'
  local source_id = request_context and request_context.source_id or config.message_source_id
  local selection = ai_provider.get_source_selection(source_id)
  local local_provider = selection and selection.provider or ai_provider.get_default_provider() or 'ollama'
  logger.debug(
    string.format(
      'Completing AI prompt (source=%s chars=%d selected_provider=%s selected_model=%s fallback=%s)',
      source_id,
      #full_prompt,
      tostring(local_provider),
      tostring(selection and selection.model or nil),
      tostring(config.values.provider)
    )
  )
  if status_callback then
    local action = request_context and request_context.status_action
    if action and selection and selection.model then
      status_callback(action .. ' with ' .. selection.model)
    else
      status_callback('Checking ' .. local_provider)
    end
  end

  ai_provider.check(local_provider, function(working)
    if request_context and request_context.is_cancelled and request_context.is_cancelled() then
      return
    end
    if working then
      logger.info('Routing prompt source=' .. source_id .. ' provider=' .. local_provider)
      complete_ai_provider(source_id, full_prompt, callback, status_callback, request_context)
      return
    end

    logger.info(string.format('%s unavailable for source=%s, falling back to %s provider', local_provider, source_id, config.values.provider))
    if config.values.provider == 'openrouter' then
      complete_openrouter(source_id, full_prompt, callback, status_callback, request_context)
    else
      complete_copilot(source_id, full_prompt, callback, status_callback, request_context)
    end
  end)
end

---@param session table|nil
---@param callback function(string|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
function M.summarize_session(session, callback, status_callback, request_context)
  if not session then
    callback(nil)
    return
  end

  local session_label = session.label or session.provider or 'assistant'
  if status_callback then
    status_callback('Summarizing ' .. session_label .. ' session')
  end

  local prompt = string.format(prompts.session_summary, session_label, session.title or 'Untitled', session.directory or 'unknown', session.transcript or '')
  log().debug(
    string.format(
      'Summarizing assistant session (provider=%s title=%s transcript_chars=%d prompt_chars=%d)',
      tostring(session.label or session.provider),
      tostring(session.title),
      #(session.transcript or ''),
      #prompt
    )
  )
  local summary_context = child_request_context(request_context, {
    source_id = config.summary_source_id,
    status_action = 'Summarizing ' .. session_label .. ' session',
  })

  M.complete_prompt(prompt, function(summary)
    if not summary or summary:match '^%s*$' then
      log().debug 'Assistant session summary was empty'
      callback(nil)
      return
    end
    log().debug('Assistant session summary generated (chars=' .. tostring(#summary) .. ')')
    callback(summary)
  end, status_callback, summary_context)
end

---@param branch string
---@param recent_commits string
---@param session_summary string|nil
---@param diff string
---@param callback function(string|nil, table|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
function M.generate_commit_message(branch, recent_commits, session_summary, diff, callback, status_callback, request_context)
  local session_context = session_summary
  if type(session_context) ~= 'string' or session_context:match '^%s*$' then
    session_context = 'No recent assistant session context available.'
  end
  local prompt = string.format(prompts.commit, branch, recent_commits, session_context, diff)
  log().debug(
    string.format(
      'Commit prompt built (branch=%s commits_chars=%d session_context_chars=%d diff_chars=%d prompt_chars=%d has_session_context=%s)',
      branch,
      #recent_commits,
      #session_context,
      #diff,
      #prompt,
      session_summary and 'yes' or 'no'
    )
  )
  dump_prompt(prompt)
  request_context = child_request_context(request_context, {
    source_id = config.message_source_id,
  })
  M.complete_prompt(prompt, callback, status_callback, request_context)
end

return M
