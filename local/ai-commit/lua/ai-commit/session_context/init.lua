local config = require 'ai-commit.config'
local git = require 'ai-commit.session_context.git'
local log = require('ai-commit.log').get

local providers = {
  require('ai-commit.session_context.opencode').get_recent,
}

local M = {}

M.comment_char = git.comment_char

---@param callback function(table|nil)
---@param status_callback function(string)|nil
function M.get_recent(callback, status_callback)
  local logger = log()
  local index = 1

  local function try_next()
    local provider = providers[index]
    index = index + 1

    if not provider then
      logger.debug 'No assistant session context provider returned context'
      callback(nil)
      return
    end

    logger.debug('Trying assistant session context provider #' .. tostring(index - 1))
    provider(function(session)
      if session then
        logger.debug('Assistant session context provider returned ' .. tostring(session.label or session.provider or 'unknown'))
        callback(session)
        return
      end
      try_next()
    end, status_callback)
  end

  try_next()
end

---@param opts table|nil
---@return table
local function collection_plan(opts)
  local context_opts = config.values.context or {}
  local refinement_opts = config.values.refinement or {}
  local refinement_context_opts = refinement_opts.include_context or {}
  local plan = {
    recent_commits = context_opts.recent_commits ~= false,
    opencode = context_opts.opencode ~= false,
    staged_changes = context_opts.staged_changes ~= false,
    refinement_recent_commits = refinement_opts.enabled ~= false
      and refinement_opts.recent_commits_with_body ~= false
      and refinement_context_opts.recent_commits ~= false,
  }

  if opts and type(opts.include) == 'table' then
    plan = vim.tbl_extend('force', plan, opts.include)
  end

  return plan
end

---@param callback function(table|nil)
---@param opts table|nil
function M.collect(callback, opts)
  opts = opts or {}
  local logger = log()
  local plan = collection_plan(opts)
  local context = {}
  local total = 2
  local done_count = 0
  local pending = total
  local failed = false
  local finished = false

  if plan.recent_commits then
    total = total + 1
    pending = pending + 1
  end
  if plan.opencode then
    total = total + 1
    pending = pending + 1
  end
  if plan.staged_changes then
    total = total + 1
    pending = pending + 1
  end
  if plan.refinement_recent_commits then
    total = total + 1
    pending = pending + 1
  end

  local function is_cancelled()
    return opts.is_cancelled and opts.is_cancelled()
  end

  local function notify_update()
    if opts.on_update then
      opts.on_update(context)
    end
  end

  local function status(text)
    if opts.status_callback then
      opts.status_callback(text)
    end
  end

  local function finish(result)
    if finished then
      return
    end
    finished = true
    callback(result)
  end

  local function mark_done()
    if is_cancelled() or finished then
      return
    end
    done_count = done_count + 1
    status(string.format('Preparing context (%d/%d)', done_count, total))
    pending = pending - 1
    notify_update()
    if pending == 0 and not failed then
      finish(context)
    elseif failed then
      finish(nil)
    end
  end

  local function mark_failed()
    failed = true
    finish(nil)
  end

  notify_update()
  status(string.format('Preparing context (%d/%d)', done_count, total))

  git.current_branch(function(branch)
    if is_cancelled() or finished then
      return
    end
    context.branch = branch
    logger.debug('Git branch context ready: ' .. tostring(branch))
    mark_done()
  end)

  git.staged_diff_stat(function(diff_stat)
    if is_cancelled() or finished then
      return
    end
    if not diff_stat then
      mark_failed()
      return
    end
    context.diff_stat = diff_stat
    logger.debug('Staged diff stat context ready (chars=' .. tostring(#diff_stat) .. ')')
    mark_done()
  end)

  if plan.recent_commits then
    git.recent_commits(5, function(commits)
      if is_cancelled() or finished then
        return
      end
      context.recent_commits = commits
      logger.debug('Recent commit context ready (chars=' .. tostring(#commits) .. ')')
      mark_done()
    end)
  end

  if plan.refinement_recent_commits then
    git.recent_commits(5, function(commits)
      if is_cancelled() or finished then
        return
      end
      context.refinement_recent_commits = commits
      logger.debug('Refinement recent commit context ready (chars=' .. tostring(#commits) .. ')')
      mark_done()
    end, true)
  end

  if plan.opencode then
    M.get_recent(function(session)
      if is_cancelled() or finished then
        return
      end
      if not session then
        logger.debug 'No assistant session context available'
        mark_done()
        return
      end
      logger.debug(
        'Assistant session context loaded (provider='
          .. tostring(session.label or session.provider)
          .. ' transcript_chars='
          .. tostring(#(session.transcript or ''))
          .. ')'
      )
      if not opts.summarize_session then
        mark_done()
        return
      end
      opts.summarize_session(session, function(summary)
        if is_cancelled() or finished then
          return
        end
        context.session_summary = summary
        logger.debug('Assistant session summary ready (chars=' .. tostring(summary and #summary or 0) .. ')')
        mark_done()
      end)
    end, status)
  end

  if plan.staged_changes then
    git.staged_diff(function(diff, diff_meta)
      if is_cancelled() or finished then
        return
      end
      if not diff then
        mark_failed()
        return
      end
      context.diff = diff
      context.diff_meta = diff_meta
      logger.debug(
        string.format(
          'Staged diff context ready (chars=%d changed_lines=%s context_lines=%s truncated=%s original_chars=%s)',
          #diff,
          tostring(diff_meta and diff_meta.changed_lines),
          tostring(diff_meta and diff_meta.context_lines),
          tostring(diff_meta and diff_meta.truncated),
          tostring(diff_meta and diff_meta.original_chars)
        )
      )
      mark_done()
    end)
  end
end

return M
