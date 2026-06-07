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
function M.complete_prompt(full_prompt, callback, status_callback, request_context)
  local logger = log()
  local ai_provider = require 'ai-provider'
  local source_id = request_context and request_context.source_id or config.message_source_id
  local selection = ai_provider.get_source_selection(source_id)
  local provider = selection and selection.provider or ai_provider.get_default_provider() or 'ollama'
  logger.debug(
    string.format(
      'Completing AI prompt (source=%s chars=%d provider=%s model=%s)',
      source_id,
      #full_prompt,
      tostring(provider),
      tostring(selection and selection.model or nil)
    )
  )
  if status_callback then
    local action = request_context and request_context.status_action
    if action and selection and selection.model then
      status_callback(action .. ' with ' .. selection.model)
    else
      status_callback('Checking ' .. provider)
    end
  end

  ai_provider.check(provider, function(working)
    if request_context and request_context.is_cancelled and request_context.is_cancelled() then
      return
    end
    if working then
      logger.info('Routing prompt source=' .. source_id .. ' provider=' .. provider)
      complete_ai_provider(source_id, full_prompt, callback, status_callback, request_context)
      return
    end

    logger.error(string.format('AI provider %s unavailable for source=%s', provider, source_id))
    vim.notify('AI provider ' .. provider .. ' unavailable. Check :AIProvider.', vim.log.levels.ERROR)
    callback(nil, nil)
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
---@param diff_stat string
---@param diff string
---@param callback function(string|nil, table|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
function M.generate_commit_message(branch, recent_commits, session_summary, diff_stat, diff, callback, status_callback, request_context)
  local sections = {}
  if type(diff_stat) == 'string' and not diff_stat:match '^%s*$' then
    table.insert(sections, { title = 'Staged files', body = diff_stat, fenced = true })
  end
  if type(recent_commits) == 'string' and not recent_commits:match '^%s*$' then
    table.insert(sections, { title = 'Recent commits', body = recent_commits })
  end
  if type(session_summary) == 'string' and not session_summary:match '^%s*$' then
    table.insert(sections, { title = 'Recent assistant session context', body = session_summary })
  end
  if type(diff) == 'string' and not diff:match '^%s*$' then
    table.insert(sections, { title = 'Staged changes', body = diff, fenced = true })
  end
  local prompt = prompts.commit(branch, sections)
  log().debug(
    string.format(
      'Commit prompt built (branch=%s commits_chars=%d session_context_chars=%d diff_stat_chars=%d diff_chars=%d prompt_chars=%d has_session_context=%s)',
      branch,
      type(recent_commits) == 'string' and #recent_commits or 0,
      type(session_summary) == 'string' and #session_summary or 0,
      type(diff_stat) == 'string' and #diff_stat or 0,
      type(diff) == 'string' and #diff or 0,
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
