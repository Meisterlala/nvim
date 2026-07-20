local config = require 'ai-commit.config'
local heuristics = require 'ai-commit.heuristics'
local log = require('ai-commit.log').get
local prompts = require 'ai-commit.prompts'
local util = require 'ai-commit.util'

local M = {}

local function sanitize_filename_part(value)
  value = tostring(value or 'unknown'):gsub('[^%w_.-]+', '-')
  value = value:gsub('^-+', ''):gsub('-+$', '')
  return value ~= '' and value or 'unknown'
end

local function git_short_hash()
  local hash = vim.fn.system({ 'git', 'rev-parse', '--short', 'HEAD' }):gsub('%s+$', '')
  if vim.v.shell_error ~= 0 or hash == '' then
    return 'no-head'
  end
  return hash
end

local function git_current_branch()
  local branch = vim.fn.system({ 'git', 'branch', '--show-current' }):gsub('%s+$', '')
  if vim.v.shell_error ~= 0 or branch == '' then
    return 'unknown'
  end
  return branch
end

local function dump_prompt(prompt, reason, branch)
  if config.values.log_level ~= 'debug' then
    return
  end

  local paths = {}
  local dump_dir = config.values.prompt_dump_dir
  if type(dump_dir) == 'string' and dump_dir ~= '' then
    local timestamp = os.date '%Y%m%d-%H%M%S'
    local filename = string.format(
      '%s-%s-%s-%s.md',
      timestamp,
      sanitize_filename_part(branch or git_current_branch()),
      sanitize_filename_part(git_short_hash()),
      sanitize_filename_part(reason or 'prompt')
    )
    table.insert(paths, dump_dir .. '/' .. filename)
  end

  if #paths == 0 then
    return
  end

  local logger = log()
  for _, path in ipairs(paths) do
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
end

local function child_request_context(request_context, overrides)
  return vim.tbl_extend('force', request_context or {}, overrides or {})
end

local function provider_label(provider)
  if type(provider) ~= 'string' or provider == '' then
    return 'AI provider'
  end
  return provider:sub(1, 1):upper() .. provider:sub(2)
end

local function format_error_detail(meta)
  if type(meta) ~= 'table' then
    return 'unknown error'
  end

  local parts = { tostring(meta.error or 'unknown error') }
  if meta.done_reason then
    table.insert(parts, 'done_reason=' .. tostring(meta.done_reason))
  end
  if meta.requested_model then
    table.insert(parts, 'requested_model=' .. tostring(meta.requested_model))
  end
  if meta.used_model then
    table.insert(parts, 'used_model=' .. tostring(meta.used_model))
  end
  if meta.elapsed_ms then
    table.insert(parts, string.format('elapsed=%.1fs', meta.elapsed_ms / 1000))
  end
  if meta.load_duration then
    table.insert(parts, string.format('load=%.1fs', meta.load_duration / 1e9))
  end
  if meta.prompt_eval_count then
    table.insert(parts, 'prompt_tokens=' .. tostring(meta.prompt_eval_count))
  end
  if meta.eval_count then
    table.insert(parts, 'eval_tokens=' .. tostring(meta.eval_count))
  end

  return table.concat(parts, ' | ')
end

local function format_error_summary(provider, meta)
  local error = type(meta) == 'table' and tostring(meta.error or '') or ''
  if error:match 'timed out' or error:match 'Operation timed out' then
    return provider .. ' request timed out while waiting for the model.'
  end
  if type(meta) == 'table' and meta.done_reason == 'length' then
    return provider .. ' stopped because the output or context limit was reached.'
  end
  if error ~= '' and error ~= 'unknown error' then
    return provider .. ' request failed: ' .. error
  end
  return provider .. ' request failed. See ai-commit logs for details.'
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

function M.select_refinement_model()
  local logger = log()
  local ai_provider = require 'ai-provider'
  logger.info('Opening AI provider model picker for source=' .. config.refine_source_id)
  ai_provider.select_source_model(config.refine_source_id)
end

---@param full_prompt string
---@param callback function(string|nil, table|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
local function complete_ai_provider(source_id, full_prompt, callback, status_callback, request_context)
  local logger = log()
  local ai_provider = require 'ai-provider'
  local selection = ai_provider.get_source_selection(source_id)
  local provider = selection and selection.provider or ai_provider.get_default_provider()

  if not provider then
    logger.error('No AI provider selected for source=' .. source_id)
    vim.notify('No AI provider selected. Check :AIProvider.', vim.log.levels.ERROR)
    callback(nil, nil)
    return
  end

  local model = selection and selection.model or ai_provider.get_selected_model(provider, source_id)

  if not model then
    logger.error('No AI provider model selected for source=' .. source_id .. ' provider=' .. provider)
    vim.notify('No AI model selected. Run :AIProvider source ' .. source_id .. ' model first.', vim.log.levels.ERROR)
    callback(nil, nil)
    return
  end

  local function report_provider_status(status)
    if not status_callback or type(status) ~= 'table' then
      return
    end
    local status_model = status.model or model
    local action = request_context and request_context.status_action
    local label = provider_label(status.provider or provider)
    if status.phase == 'loading' then
      status_callback(label .. ': Loading model ' .. status_model)
    elseif status.phase == 'loaded' then
      status_callback(label .. ': Loaded model ' .. status_model)
    elseif status.phase == 'context' then
      status_callback((action or 'Generating response') .. ' with ' .. status_model .. ' (loading context)')
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

  if request_context and request_context.on_request_start then
    request_context.on_request_start(source_id, model)
  end

  ai_provider.chat(provider, {
    source_id = source_id,
    model = model,
    prompt = full_prompt,
    stream = true,
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
        local detail = format_error_detail(meta)
        logger.error(provider .. ' chat request failed: ' .. detail)
        vim.notify(format_error_summary(provider, meta), vim.log.levels.ERROR)
        callback(nil, meta)
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
  local provider = selection and selection.provider or ai_provider.get_default_provider()
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
    if not provider then
      status_callback 'No AI provider selected'
    else
      status_callback(provider_label(provider) .. ': Checking')
    end
  end

  if not provider then
    logger.error('No AI provider selected for source=' .. source_id)
    vim.notify('No AI provider selected. Check :AIProvider.', vim.log.levels.ERROR)
    callback(nil, nil)
    return
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
    status_callback(session_label .. ': Loading session context')
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
  dump_prompt(prompt, 'opencode-summary')
  local summary_context = child_request_context(request_context, {
    source_id = config.summary_source_id,
    status_action = session_label .. ': Summarizing session',
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

local function generation_sections(recent_commits, session_summary, diff_stat, diff)
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
  return sections
end

local function truncate_middle(text, max_chars, label)
  if type(text) ~= 'string' or #text <= max_chars then
    return text, false
  end

  max_chars = math.max(0, max_chars)
  local marker = string.format('\n\n[... %s truncated by ai-commit: original=%d chars, kept=%d chars ...]\n\n', label or 'content', #text, max_chars)
  if max_chars <= #marker then
    return marker, true
  end

  local remaining = max_chars - #marker
  local head_len = math.floor(remaining * 0.7)
  local tail_len = remaining - head_len
  local tail_start = math.max(1, #text - tail_len + 1)
  return text:sub(1, head_len) .. marker .. text:sub(tail_start), true
end

local function selected_context_size(source_id)
  local ok, ai_provider = pcall(require, 'ai-provider')
  if not ok then
    return nil
  end

  local selection = ai_provider.get_source_selection(source_id)
  local provider = selection and selection.provider or ai_provider.get_default_provider()
  if not provider then
    return nil
  end

  local model = selection and selection.model or ai_provider.get_selected_model(provider, source_id)
  local provider_config = ai_provider.get_provider_config(provider)
  if type(provider_config) ~= 'table' then
    return nil
  end

  local model_config = provider_config.models and provider_config.models[model]
  if type(model_config) == 'table' and type(model_config.context_size) == 'number' then
    return model_config.context_size
  end
  if type(provider_config.context_size) == 'number' then
    return provider_config.context_size
  end
  return nil
end

local function prompt_budget_chars(source_id)
  local context_size = selected_context_size(source_id)
  if not context_size then
    return nil, nil
  end

  local ratio = tonumber(config.values.prompt_context_ratio) or 0.8
  ratio = math.max(0.1, math.min(ratio, 1))
  local chars_per_token = tonumber(config.values.prompt_chars_per_token) or 3
  chars_per_token = math.max(1, chars_per_token)
  return math.floor(context_size * ratio * chars_per_token), context_size
end

local function commit_prompt_with_budget(branch, recent_commits, session_summary, diff_stat, diff)
  local sections = generation_sections(recent_commits, session_summary, diff_stat, diff)
  local prompt = prompts.commit(branch, sections)
  local max_prompt_chars, context_size = prompt_budget_chars(config.message_source_id)
  if not max_prompt_chars or max_prompt_chars <= 0 or #prompt <= max_prompt_chars or type(diff) ~= 'string' or diff == '' then
    return prompt, sections, diff, false, context_size, max_prompt_chars
  end

  local excess = #prompt - max_prompt_chars
  local diff_budget = math.max(0, #diff - excess - 512)
  local truncated_diff, truncated = truncate_middle(diff, diff_budget, 'staged changes')
  if not truncated then
    return prompt, sections, diff, false, context_size, max_prompt_chars
  end

  sections = generation_sections(recent_commits, session_summary, diff_stat, truncated_diff)
  prompt = prompts.commit(branch, sections)
  while #prompt > max_prompt_chars and diff_budget > 0 do
    diff_budget = math.floor(diff_budget * 0.75)
    truncated_diff = truncate_middle(diff, diff_budget, 'staged changes')
    sections = generation_sections(recent_commits, session_summary, diff_stat, truncated_diff)
    prompt = prompts.commit(branch, sections)
  end

  log().warn(
    string.format(
      'Commit prompt exceeded max size, trimmed staged changes (max_prompt_chars=%d prompt_chars=%d original_diff_chars=%d sent_diff_chars=%d)',
      max_prompt_chars,
      #prompt,
      #diff,
      #truncated_diff
    )
  )
  return prompt, sections, truncated_diff, true, context_size, max_prompt_chars
end

local function refinement_sections(context)
  local refinement = config.values.refinement or {}
  local include = refinement.include_context or {}
  local sections = {}

  if include.staged_files ~= false and type(context.diff_stat) == 'string' and not context.diff_stat:match '^%s*$' then
    table.insert(sections, { title = 'Staged files', body = context.diff_stat, fenced = true })
  end
  if include.recent_commits ~= false then
    local commits = context.refinement_recent_commits or context.recent_commits
    if type(commits) == 'string' and not commits:match '^%s*$' then
      table.insert(sections, { title = 'Recent commits with bodies', body = commits })
    end
  end
  if include.session_context ~= false and type(context.session_summary) == 'string' and not context.session_summary:match '^%s*$' then
    table.insert(sections, { title = 'Recent assistant session context', body = context.session_summary })
  end
  if include.staged_changes ~= false and type(context.diff) == 'string' and not context.diff:match '^%s*$' then
    table.insert(sections, { title = 'Staged changes', body = context.diff, fenced = true })
  end

  return sections
end

local function maybe_refine_message(context, message, iteration, callback, status_callback, request_context)
  message = heuristics.normalize(message) or message
  local refinement = config.values.refinement or {}
  if refinement.enabled == false then
    callback(message)
    return
  end

  local validation = heuristics.validate(message)
  if validation.valid then
    if validation.warnings and #validation.warnings > 0 then
      log().debug('Commit message passed heuristics with warnings: ' .. table.concat(validation.warnings, '; '))
    end
    log().debug('Commit message passed heuristics after ' .. tostring(iteration) .. ' refinement(s)')
    callback(message)
    return
  end

  local max_iterations = tonumber(refinement.max_iterations) or 0
  if iteration >= max_iterations then
    log().warn('Commit message failed heuristics after max refinements: ' .. heuristics.format_failures(validation):gsub('\n', '; '))
    callback(message)
    return
  end

  local next_iteration = iteration + 1
  local failures = heuristics.format_failures(validation)
  local prompt = prompts.refine_commit(context.branch or 'unknown', message or '', failures, refinement_sections(context))
  log().debug(string.format('Refinement prompt built (iteration=%d prompt_chars=%d failures=%d)', next_iteration, #prompt, #validation.failures))
  dump_prompt(prompt, 'refinement-' .. tostring(next_iteration), context.branch)

  local refinement_context = child_request_context(request_context, {
    source_id = config.refine_source_id,
    status_action = tostring(next_iteration) .. '. Refinement',
  })
  M.complete_prompt(prompt, function(refined_message)
    if not refined_message then
      callback(nil)
      return
    end
    maybe_refine_message(context, refined_message, next_iteration, callback, status_callback, request_context)
  end, status_callback, refinement_context)
end

---@param branch string
---@param recent_commits string
---@param session_summary string|nil
---@param diff_stat string
---@param diff string
---@param refinement_recent_commits string|nil
---@param callback function(string|nil, table|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
function M.generate_commit_message(
  branch,
  recent_commits,
  session_summary,
  diff_stat,
  diff,
  refinement_recent_commits,
  callback,
  status_callback,
  request_context
)
  local context = {
    branch = branch,
    recent_commits = recent_commits,
    refinement_recent_commits = refinement_recent_commits,
    session_summary = session_summary,
    diff_stat = diff_stat,
    diff = diff,
  }
  local prompt, _, prompt_diff, prompt_truncated, context_size, max_prompt_chars = commit_prompt_with_budget(branch, recent_commits, session_summary, diff_stat, diff)
  context.diff = prompt_diff
  log().debug(
    string.format(
      'Commit prompt built (branch=%s commits_chars=%d session_context_chars=%d diff_stat_chars=%d diff_chars=%d prompt_chars=%d context_size=%s max_prompt_chars=%s has_session_context=%s prompt_truncated=%s)',
      branch,
      type(recent_commits) == 'string' and #recent_commits or 0,
      type(session_summary) == 'string' and #session_summary or 0,
      type(diff_stat) == 'string' and #diff_stat or 0,
      type(prompt_diff) == 'string' and #prompt_diff or 0,
      #prompt,
      tostring(context_size),
      tostring(max_prompt_chars),
      session_summary and 'yes' or 'no',
      tostring(prompt_truncated)
    )
  )
  dump_prompt(prompt, 'generate-message', branch)
  request_context = child_request_context(request_context, {
    source_id = config.message_source_id,
  })
  M.complete_prompt(prompt, function(message, meta)
    if not message then
      callback(nil, meta)
      return
    end
    maybe_refine_message(context, message, 0, function(final_message)
      callback(final_message, meta)
    end, status_callback, request_context)
  end, status_callback, request_context)
end

return M
