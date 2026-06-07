local providers = {
  require('ai-commit.session_context.opencode').get_recent,
}

local M = {}

---@param callback function(table|nil)
---@param status_callback function(string)|nil
function M.get_recent(callback, status_callback)
  local log = require('ai-commit.log').get()
  local index = 1

  local function try_next()
    local provider = providers[index]
    index = index + 1

    if not provider then
      log.debug 'No assistant session context provider returned context'
      callback(nil)
      return
    end

    log.debug('Trying assistant session context provider #' .. tostring(index - 1))
    provider(function(session)
      if session then
        log.debug('Assistant session context provider returned ' .. tostring(session.label or session.provider or 'unknown'))
        callback(session)
        return
      end
      try_next()
    end, status_callback)
  end

  try_next()
end

return M
