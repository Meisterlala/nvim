local config = require 'ai-commit.config'
local state = require 'ai-commit.state'

local M = {}

---@return table
function M.get()
  if state.log then
    return state.log
  end

  local ok, plenary_log = pcall(require, 'plenary.log')
  if not ok then
    local noop = function() end
    state.log = { debug = noop, info = noop, warn = noop, error = noop }
    return state.log
  end

  state.log = plenary_log.new {
    plugin = 'ai-commit',
    level = config.values.log_level or 'info',
    use_console = false,
  }

  return state.log
end

return M
