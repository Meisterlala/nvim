local M = {}

local ignored_context_tags = {
  'system-reminder',
}

---@param value string
---@return string
local function escape_pattern(value)
  return value:gsub('([^%w])', '%%%1')
end

---@param message string
---@return string
function M.clean_message(message)
  return message:gsub('^%s*```.-\n', ''):gsub('\n```%s*$', ''):gsub('^%s+', ''):gsub('%s+$', '')
end

---@param text string|nil
---@param max_chars integer
---@return string
function M.truncate_text(text, max_chars)
  if type(text) ~= 'string' then
    return ''
  end
  if #text <= max_chars then
    return text
  end
  return text:sub(1, max_chars) .. '\n[... truncated ...]'
end

---@param text string
---@return string
function M.strip_relevant_memories(text)
  local stripped = text:gsub('^%s*<relevant%-memories>.-</relevant%-memories>%s*', '')
  stripped = stripped:gsub('^%s*Use `memread` with.-\n', '')
  return stripped:gsub('^%s+', '')
end

---@param text string
---@return string
function M.strip_ignored_context_blocks(text)
  local stripped = text
  for _, tag in ipairs(ignored_context_tags) do
    local escaped = escape_pattern(tag)
    stripped = stripped:gsub('%s*<' .. escaped .. '>.-</' .. escaped .. '>%s*', '\n[removed ' .. tag .. ']\n')
  end
  return stripped:gsub('\n\n\n+', '\n\n'):gsub('^%s+', ''):gsub('%s+$', '')
end

return M
