local config = require 'ai-commit.config'
local log = require('ai-commit.log').get

local M = {}

---@return string
function M.comment_char()
  local result = vim.fn.system('git config core.commentChar'):gsub('%s+$', '')
  if result == '' or result == 'auto' then
    return '#'
  end
  return result
end

---@param callback function(string)
function M.current_branch(callback)
  local Job = require 'plenary.job'
  Job:new({
    command = 'git',
    args = { 'branch', '--show-current' },
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        callback 'unknown'
        return
      end
      callback(table.concat(job:result(), '\n'):gsub('%s+$', ''))
    end),
  }):start()
end

---@param count integer
---@param callback function(string)
function M.recent_commits(count, callback)
  local Job = require 'plenary.job'
  Job:new({
    command = 'git',
    args = { 'log', '-n', tostring(count or 5), '--format=%h %s' },
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        callback 'No recent commits available'
        return
      end
      callback(table.concat(job:result(), '\n'))
    end),
  }):start()
end

---@param numstat string[]
---@return integer
local function count_changed_lines(numstat)
  local changed_lines = 0
  for _, line in ipairs(numstat) do
    local additions, deletions = line:match '^(%S+)%s+(%S+)%s+'
    additions = tonumber(additions) or 0
    deletions = tonumber(deletions) or 0
    changed_lines = changed_lines + additions + deletions
  end
  return changed_lines
end

---@param changed_lines integer
---@return integer
local function diff_context_lines(changed_lines)
  local diff_context = config.values.diff_context or {}
  if changed_lines <= (diff_context.small_changed_lines or 100) then
    return 2
  end
  if changed_lines <= (diff_context.medium_changed_lines or 500) then
    return 1
  end
  return 0
end

---@param callback function(string|nil, table|nil)
function M.staged_diff(callback)
  local logger = log()
  logger.debug 'Getting staged changes diff'

  local Job = require 'plenary.job'
  Job
    :new({
      command = 'git',
      args = { 'diff', '--cached', '--no-color', '--no-ext-diff', '--numstat' },
      on_exit = vim.schedule_wrap(function(numstat_job, numstat_code)
        if numstat_code ~= 0 then
          logger.error 'Failed to get staged changes numstat'
          callback(nil, nil)
          return
        end

        local changed_lines = count_changed_lines(numstat_job:result())
        local unified = diff_context_lines(changed_lines)
        logger.debug(string.format('Staged diff changed lines=%d using unified=%d', changed_lines, unified))

        Job
          :new({
            command = 'git',
            args = { 'diff', '--cached', '--no-color', '--no-ext-diff', '--unified=' .. tostring(unified) },
            on_exit = vim.schedule_wrap(function(job, code)
              if code ~= 0 then
                logger.error 'Failed to get staged changes'
                callback(nil, nil)
                return
              end

              local result = table.concat(job:result(), '\n')
              if result == '' or result:match '^%s*$' then
                logger.warn 'No staged changes found'
                callback(nil, nil)
                return
              end

              local diff_meta = {
                changed_lines = changed_lines,
                context_lines = unified,
                original_chars = #result,
                sent_chars = #result,
                truncated = false,
              }

              if #result > config.values.max_diff_chars then
                local head_len = math.floor(config.values.max_diff_chars * 0.7)
                local tail_len = config.values.max_diff_chars - head_len
                local tail_start = math.max(1, #result - tail_len + 1)
                local marker =
                  string.format('\n\n[... diff truncated by ai_commit: original=%d chars, kept=%d chars ...]\n\n', #result, config.values.max_diff_chars)
                result = result:sub(1, head_len) .. marker .. result:sub(tail_start)
                diff_meta.truncated = true
                diff_meta.sent_chars = #result
                logger.warn(string.format('Staged diff exceeded max size, truncated to %d chars', config.values.max_diff_chars))
              end

              logger.info(string.format('Got staged diff (%d bytes, changed_lines=%d, unified=%d)', #result, changed_lines, unified))
              callback(result, diff_meta)
            end),
          })
          :start()
      end),
    })
    :start()
end

---@param callback function(string|nil)
function M.staged_diff_stat(callback)
  local logger = log()
  logger.debug 'Getting staged changes diff stat'

  local Job = require 'plenary.job'
  Job:new({
    command = 'git',
    args = { 'diff', '--cached', '--no-color', '--no-ext-diff', '--stat' },
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        logger.error 'Failed to get staged changes diff stat'
        callback(nil)
        return
      end

      local result = table.concat(job:result(), '\n')
      if result == '' or result:match '^%s*$' then
        logger.warn 'No staged changes diff stat found'
        callback(nil)
        return
      end

      logger.info(string.format('Got staged diff stat (%d bytes)', #result))
      callback(result)
    end),
  }):start()
end

return M
