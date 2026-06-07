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

---@param callback function(string|nil, table|nil)
function M.staged_diff(callback)
  local logger = log()
  logger.debug 'Getting staged changes diff'

  local Job = require 'plenary.job'
  Job:new({
    command = 'git',
    args = { 'diff', '--cached', '--no-color', '--no-ext-diff' },
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
        original_chars = #result,
        sent_chars = #result,
        truncated = false,
      }

      if #result > config.values.max_diff_chars then
        local head_len = math.floor(config.values.max_diff_chars * 0.7)
        local tail_len = config.values.max_diff_chars - head_len
        local tail_start = math.max(1, #result - tail_len + 1)
        local marker = string.format('\n\n[... diff truncated by ai_commit: original=%d chars, kept=%d chars ...]\n\n', #result, config.values.max_diff_chars)
        result = result:sub(1, head_len) .. marker .. result:sub(tail_start)
        diff_meta.truncated = true
        diff_meta.sent_chars = #result
        logger.warn(string.format('Staged diff exceeded max size, truncated to %d chars', config.values.max_diff_chars))
      end

      logger.info(string.format('Got staged diff (%d bytes)', #result))
      callback(result, diff_meta)
    end),
  }):start()
end

return M
