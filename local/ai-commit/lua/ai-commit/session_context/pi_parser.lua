local util = require 'ai-commit.util'

local M = {}

---@param content any
---@return string
local function content_text(content)
  if type(content) == 'string' then
    return content
  end
  if type(content) ~= 'table' then
    return ''
  end

  local parts = {}
  for _, part in ipairs(content) do
    if type(part) == 'table' and part.type == 'text' and type(part.text) == 'string' and part.text ~= '' then
      table.insert(parts, part.text)
    end
  end
  return table.concat(parts, '\n')
end

---@param message table
---@return table|nil
local function transcript_item(message)
  if type(message) ~= 'table' or (message.role ~= 'user' and message.role ~= 'assistant') then
    return nil
  end

  local text = util.strip_ignored_context_blocks(util.strip_relevant_memories(content_text(message.content)))
  if text == '' then
    return nil
  end
  return { role = message.role, text = text }
end

---@param entry table
---@return table|nil
local function entry_item(entry)
  if entry.type == 'message' then
    return transcript_item(entry.message)
  end
  if entry.type == 'compaction' and type(entry.summary) == 'string' and entry.summary ~= '' then
    return { role = 'summary', kind = 'compaction', text = entry.summary }
  end
  if entry.type == 'branch_summary' and type(entry.summary) == 'string' and entry.summary ~= '' then
    return { role = 'summary', kind = 'branch', text = entry.summary }
  end
  return nil
end

---@param by_id table<string, table>
---@param leaf_id string
---@return table[]
local function active_path(by_id, leaf_id)
  local reversed = {}
  local seen = {}
  local entry = by_id[leaf_id]

  while entry and not seen[entry.id] do
    seen[entry.id] = true
    table.insert(reversed, entry)
    entry = entry.parentId and by_id[entry.parentId] or nil
  end

  local path = {}
  for index = #reversed, 1, -1 do
    table.insert(path, reversed[index])
  end
  return path
end

---@param path table[]
---@return table[]
local function context_items(path)
  local compaction_index = nil
  for index, entry in ipairs(path) do
    if entry.type == 'compaction' then
      compaction_index = index
    end
  end

  local items = {}
  local function add_entry(entry)
    local item = entry_item(entry)
    if item then
      table.insert(items, item)
    end
  end

  if not compaction_index then
    for _, entry in ipairs(path) do
      add_entry(entry)
    end
    return items
  end

  local compaction = path[compaction_index]
  add_entry(compaction)

  if type(compaction.retainedTail) == 'table' then
    for _, message in ipairs(compaction.retainedTail) do
      local item = transcript_item(message)
      if item then
        table.insert(items, item)
      end
    end
  elseif type(compaction.firstKeptEntryId) == 'string' then
    local first_kept_index = compaction_index
    for index = 1, compaction_index - 1 do
      if path[index].id == compaction.firstKeptEntryId then
        first_kept_index = index
        break
      end
    end
    for index = first_kept_index, compaction_index - 1 do
      add_entry(path[index])
    end
  end

  for index = compaction_index + 1, #path do
    add_entry(path[index])
  end
  return items
end

---@param item table
---@param max_message_chars integer
---@param label string
---@return string|nil
local function format_item(item, max_message_chars, label)
  local text = vim.trim(util.truncate_text(item.text, max_message_chars))
  if text == '' then
    return nil
  end
  text = vim.trim(text:gsub('```', ''))
  if text == '' then
    return nil
  end
  return string.format('%s:\n```\n%s\n```', label, text)
end

---@param items table[]
---@param opts table
---@return string|nil
local function build_transcript(items, opts)
  local max_message_chars = opts.max_message_chars or 5000
  local max_transcript_chars = opts.max_transcript_chars or 30000
  local user_limit = opts.recent_user_messages or 4
  local first_user_index = nil
  local final_assistant_index = nil
  local user_indexes = {}
  local has_compaction = false

  for index, item in ipairs(items) do
    if item.kind == 'compaction' then
      has_compaction = true
    end
    if item.role == 'user' then
      first_user_index = first_user_index or index
      table.insert(user_indexes, index)
    elseif item.role == 'assistant' then
      final_assistant_index = index
    end
  end

  local selected = {}
  if first_user_index and not has_compaction then
    selected[first_user_index] = true
  end
  for index, item in ipairs(items) do
    if item.role == 'summary' then
      selected[index] = true
    end
  end

  local conversation_start = nil
  local wanted_user_count = 0
  for index = #user_indexes, 1, -1 do
    if has_compaction or user_indexes[index] ~= first_user_index then
      conversation_start = user_indexes[index]
      wanted_user_count = wanted_user_count + 1
      if wanted_user_count >= user_limit then
        break
      end
    end
  end

  if conversation_start then
    for index = conversation_start, #items do
      selected[index] = true
    end
  elseif final_assistant_index then
    selected[final_assistant_index] = true
  end

  local lines = {}
  for index, item in ipairs(items) do
    if selected[index] then
      local label
      if item.kind == 'compaction' then
        label = 'Pi compaction summary'
      elseif item.kind == 'branch' then
        label = 'Pi branch summary'
      elseif index == first_user_index and not has_compaction then
        label = 'initial user message'
      elseif index == final_assistant_index then
        label = 'final assistant response'
      elseif item.role == 'user' then
        label = 'user message'
      else
        label = 'assistant response'
      end

      local formatted = format_item(item, max_message_chars, label)
      if formatted then
        table.insert(lines, formatted)
      end
    end
  end

  if #lines == 0 then
    return nil
  end
  return util.truncate_text(table.concat(lines, '\n\n'), max_transcript_chars)
end

---@param lines string[]
---@param opts table|nil
---@return table|nil
function M.parse(lines, opts)
  opts = opts or {}
  local header = nil
  local by_id = {}
  local leaf_id = nil

  for _, line in ipairs(lines or {}) do
    if line ~= '' then
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and type(decoded) == 'table' then
        if decoded.type == 'session' and not header then
          header = decoded
        elseif type(decoded.id) == 'string' then
          by_id[decoded.id] = decoded
          leaf_id = decoded.id
        end
      end
    end
  end

  if not header or header.version ~= 3 or type(header.cwd) ~= 'string' or not leaf_id then
    return nil
  end

  local path = active_path(by_id, leaf_id)
  local title = nil
  for _, entry in ipairs(path) do
    if entry.type == 'session_info' and type(entry.name) == 'string' and entry.name ~= '' then
      title = entry.name
    end
  end

  local transcript = build_transcript(context_items(path), opts)
  if not transcript then
    return nil
  end

  return {
    id = header.id,
    cwd = header.cwd,
    title = title or header.id,
    transcript = transcript,
  }
end

return M
