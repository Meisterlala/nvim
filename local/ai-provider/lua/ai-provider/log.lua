local M = {}

local state = {
  logger = nil,
}

local function setup_logger()
  if state.logger then
    return state.logger
  end

  local ok, plenary_log = pcall(require, 'plenary.log')
  if not ok then
    local noop = function() end
    state.logger = { debug = noop, info = noop, warn = noop, error = noop }
    return state.logger
  end

  state.logger = plenary_log.new {
    plugin = 'ai-provider',
    level = 'debug',
    use_console = false,
  }

  return state.logger
end

function M.debug(message)
  local logger = setup_logger()
  ---@cast logger any
  logger.debug(message)
end

function M.info(message)
  local logger = setup_logger()
  ---@cast logger any
  logger.info(message)
end

function M.warn(message)
  local logger = setup_logger()
  ---@cast logger any
  logger.warn(message)
end

function M.error(message)
  local logger = setup_logger()
  ---@cast logger any
  logger.error(message)
end

return M
