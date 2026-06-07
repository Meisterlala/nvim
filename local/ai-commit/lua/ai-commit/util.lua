local M = {}

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

return M
