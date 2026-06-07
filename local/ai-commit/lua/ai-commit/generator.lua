local config = require 'ai-commit.config'
local log = require('ai-commit.log').get
local providers = require 'ai-commit.providers'
local session_context = require 'ai-commit.session_context'
local spinner_ui = require 'ai-commit.spinner'
local state = require 'ai-commit.state'

local M = {}

---@param bufnr integer
---@return boolean
local function buffer_has_content(bufnr)
  local comment_char = session_context.comment_char()
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if not line:match('^' .. vim.pesc(comment_char)) and line:match '%S' then
      return true
    end
  end
  return false
end

---@param spinner table
---@param stage_text string
---@param diff_meta table|nil
---@param last_status_line string|nil
---@return string
local function set_stage_status(spinner, stage_text, diff_meta, last_status_line)
  local suffix = diff_meta and diff_meta.truncated and ' [truncated]' or ''
  local status_line = stage_text .. suffix
  local status_chunks = { { status_line, 'Comment' } }
  local active_prefix, active_model, active_suffix = stage_text:match '^(Generating commit message with )(.+)( %(.-%))$'

  if not active_prefix then
    active_prefix, active_model, active_suffix = stage_text:match '^(OpenCode: Summarizing session with )(.+)( %(.-%))$'
  end
  if not active_prefix then
    active_prefix, active_model, active_suffix = stage_text:match '^(%d+%. Refinement with )(.+)( %(.-%))$'
  end
  if not active_prefix then
    active_prefix, active_model = stage_text:match '^(Generating commit message with )(.+)$'
  end
  if not active_prefix then
    active_prefix, active_model = stage_text:match '^(Ollama: Loading model )(.+)$'
  end
  if not active_prefix then
    active_prefix, active_model = stage_text:match '^(Ollama: Loaded model )(.+)$'
  end
  if not active_prefix then
    active_prefix, active_model, active_suffix = stage_text:match '^(Generating response with )(.+)( %(.-%))$'
  end
  if not active_prefix then
    active_prefix, active_model, active_suffix = stage_text:match '^(Thinking with )(.+)( %(.-%))$'
  end
  if not active_prefix then
    active_prefix, active_model = stage_text:match '^(Generating response with )(.+)$'
  end
  if not active_prefix then
    active_prefix, active_model = stage_text:match '^(Thinking with )(.+)$'
  end

  if active_prefix and active_model then
    status_chunks = {
      { active_prefix, 'Comment' },
      { active_model, config.values.model_highlight_group },
    }
    if active_suffix then
      local suffix_group = active_suffix:find 't/s' and 'Number' or 'Comment'
      table.insert(status_chunks, { active_suffix, suffix_group })
    end
  end
  if suffix ~= '' and #status_chunks > 1 then
    table.insert(status_chunks, { suffix, 'Comment' })
  end

  spinner_ui.set_status(spinner, status_line, status_chunks)
  if status_line ~= last_status_line then
    log().debug('Status: ' .. status_line)
  end
  return status_line
end

function M.insert()
  local logger = log()
  if vim.bo.filetype ~= 'gitcommit' then
    logger.debug 'Not a gitcommit buffer, skipping'
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  logger.debug('Starting AI commit generation for buffer ' .. tostring(bufnr))
  if buffer_has_content(bufnr) then
    logger.debug('Skipping AI commit generation because buffer has content: ' .. tostring(bufnr))
    return
  end
  if state.in_flight_buffers[bufnr] then
    logger.debug('Skipping AI commit generation because generation is already in flight: ' .. tostring(bufnr))
    return
  end

  state.in_flight_buffers[bufnr] = true
  local spinner = spinner_ui.start(bufnr)
  local done = false
  local aborted = false
  local http_jobs = {}
  local last_status_line = nil
  local context = {}

  local function status(text)
    if done then
      return
    end
    last_status_line = set_stage_status(spinner, text, context.diff_meta, last_status_line)
  end

  local function abort_http_jobs()
    for _, job in ipairs(http_jobs) do
      if job and job.shutdown and not job.is_shutdown then
        pcall(job.shutdown, job, 0, 15)
      end
    end
    http_jobs = {}
  end

  local request_context = {
    is_cancelled = function()
      return done or aborted
    end,
    register_http_job = function(job)
      if job then
        table.insert(http_jobs, job)
      end
    end,
    on_request_start = function()
      if not done and not aborted then
        spinner_ui.start_stream_section(spinner)
      end
    end,
    on_chunk = function(chunk)
      if not done and not aborted then
        spinner_ui.append_stream(spinner, chunk)
      end
    end,
  }

  local function finalize(message)
    if done then
      return
    end
    status(message and 'Inserting message' or 'Generation failed')
    done = true
    local insert_row = spinner_ui.stop(bufnr, spinner)
    http_jobs = {}
    state.in_flight_buffers[bufnr] = nil

    if aborted or not message then
      return
    end

    if vim.api.nvim_buf_is_valid(bufnr) then
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      insert_row = math.max(0, math.min(insert_row, line_count))
      vim.api.nvim_buf_set_lines(bufnr, insert_row, insert_row, false, vim.split(message, '\n'))
      logger.info 'Successfully inserted commit message'
    end
  end

  local function abort_generation(reason)
    if done then
      return
    end
    done = true
    aborted = true
    abort_http_jobs()
    spinner_ui.stop(bufnr, spinner)
    state.in_flight_buffers[bufnr] = nil
    logger.info(string.format('Aborted AI commit message generation for buffer %d (%s)', bufnr, reason or 'unknown'))
  end

  vim.api.nvim_create_autocmd({ 'BufHidden', 'BufUnload', 'BufWipeout' }, {
    buffer = bufnr,
    once = true,
    callback = function()
      abort_generation 'buffer closed'
    end,
  })

  session_context.collect(function(collected_context)
    if done then
      return
    end
    if not collected_context then
      finalize(nil)
      return
    end
    context = collected_context
    providers.generate_commit_message(
      context.branch,
      context.recent_commits,
      context.session_summary,
      context.diff_stat,
      context.diff,
      context.refinement_recent_commits,
      function(message)
        finalize(message)
      end,
      status,
      vim.tbl_extend('force', request_context, { status_action = 'Generating commit message' })
    )
  end, {
    is_cancelled = function()
      return done or aborted
    end,
    on_update = function(updated_context)
      context = updated_context
    end,
    status_callback = status,
    summarize_session = function(session, callback)
      providers.summarize_session(session, callback, status, request_context)
    end,
  })
end

return M
