local M = {}

---@param message string
---@return string
function M.clean_message(message)
  return message:gsub('^%s*```.-\n', ''):gsub('\n```%s*$', ''):gsub('^%s+', ''):gsub('%s+$', '')
end

---@param body string|nil
---@param max_len integer|nil
---@return string
function M.format_body_for_log(body, max_len)
  if type(body) ~= 'string' then
    return '<no body>'
  end

  local compact = body:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if compact == '' then
    return '<empty body>'
  end

  local limit = max_len or 300
  if #compact <= limit then
    return compact
  end

  return compact:sub(1, limit) .. '...'
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
