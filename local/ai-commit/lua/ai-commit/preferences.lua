local config = require 'ai-commit.config'

local M = {}

---@return string|nil
local function preferences_file()
  if vim and vim.fn then
    return vim.fn.stdpath 'data' .. '/ai-commit-preferences.json'
  end
  return nil
end

function M.load()
  local path = preferences_file()
  if not path then
    return
  end

  local file = io.open(path, 'r')
  if not file then
    return
  end

  local content = file:read '*a'
  file:close()

  local ok, prefs = pcall(vim.json.decode, content)
  if ok and type(prefs) == 'table' then
    config.values.provider = prefs.provider or 'copilot'
    config.values.model = prefs.model
    if type(prefs.model_name) == 'string' and prefs.model_name ~= '' then
      config.values.model_name = prefs.model_name
    else
      config.values.model_name = nil
    end
  end
end

---@return boolean
function M.save()
  local path = preferences_file()
  if not path then
    return false
  end

  local file = io.open(path, 'w')
  if not file then
    return false
  end

  file:write(vim.json.encode {
    provider = config.values.provider,
    model = config.values.model,
    model_name = config.values.model_name,
  })
  file:close()
  return true
end

return M
