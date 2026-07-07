local config = require 'ai-commit.config'
local log = require('ai-commit.log').get
local util = require 'ai-commit.util'

local M = {}

---@param cwd string
---@return string
local function encode_project_dir(cwd)
  return (cwd:gsub('[/.]', '-'))
end

---@param message table
---@return string
local function message_text(message)
  local parts = {}
  local content = message.content
  if type(content) == 'string' then
    if content ~= '' then
      table.insert(parts, content)
    end
  elseif type(content) == 'table' then
    for _, part in ipairs(content) do
      if type(part) == 'table' and part.type == 'text' and type(part.text) == 'string' and part.text ~= '' then
        table.insert(parts, part.text)
      end
    end
  end
  return util.strip_ignored_context_blocks(util.strip_relevant_memories(table.concat(parts, '\n')))
end

---@param text string
---@param max_message_chars integer
---@param label string
---@return string|nil
local function format_message(text, max_message_chars, label)
  text = vim.trim(util.truncate_text(text, max_message_chars))
  if text == '' then
    return nil
  end
  text = vim.trim(text:gsub('```', ''))
  if text == '' then
    return nil
  end
  return string.format('%s:\n```\n%s\n```', label, text)
end

---@param lines string[]
---@return table[]
local function parse_entries(lines)
  local entries = {}
  for _, line in ipairs(lines) do
    if line ~= '' then
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and type(decoded) == 'table' and not decoded.isSidechain and not decoded.isMeta then
        local message = decoded.message
        if message and (decoded.type == 'user' or decoded.type == 'assistant') and type(message.role) == 'string' then
          table.insert(entries, {
            id = #entries + 1,
            role = message.role,
            text = message_text(message),
          })
        end
      end
    end
  end
  return entries
end

---@param entries table[]
---@return string|nil
local function build_transcript(entries)
  local logger = log()
  local opts = config.values.claude_context or {}
  local max_message_chars = opts.max_message_chars or 5000
  local max_transcript_chars = opts.max_transcript_chars or 30000
  local user_limit = opts.recent_user_messages or 4

  local usable = {}
  for _, entry in ipairs(entries) do
    if entry.text ~= '' then
      table.insert(usable, entry)
    end
  end

  if #usable == 0 then
    logger.debug 'Claude Code transcript selection found no usable messages'
    return nil
  end

  local first_user = nil
  for _, entry in ipairs(usable) do
    if entry.role == 'user' then
      first_user = entry
      break
    end
  end

  local user_count = 0
  local tail_start = #usable + 1
  for i = #usable, 1, -1 do
    local entry = usable[i]
    if entry.role == 'user' and entry ~= first_user then
      user_count = user_count + 1
      tail_start = i
      if user_count >= user_limit then
        break
      end
    end
  end

  local lines = {}
  if first_user then
    local formatted = format_message(first_user.text, max_message_chars, 'initial user message')
    if formatted then
      table.insert(lines, formatted)
    end
  end

  if tail_start <= #usable then
    table.insert(lines, 'Tail of the Session:')
    for i = tail_start, #usable do
      local entry = usable[i]
      if entry ~= first_user then
        local label = (i == #usable and entry.role == 'assistant') and 'final assistant response'
          or (entry.role == 'user' and 'user message' or 'assistant response')
        local formatted = format_message(entry.text, max_message_chars, label)
        if formatted then
          table.insert(lines, formatted)
        end
      end
    end
  end

  if #lines == 0 then
    logger.debug 'Claude Code transcript selection was empty after formatting'
    return nil
  end

  local transcript = util.truncate_text(table.concat(lines, '\n\n'), max_transcript_chars)
  logger.debug(string.format('Claude Code transcript built (entries=%d usable=%d chars=%d)', #entries, #usable, #transcript))
  return transcript
end

---@param dir string
---@param recent_ms integer
---@return string|nil
local function find_recent_session_file(dir, recent_ms)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return nil
  end
  local cutoff = os.time() - math.floor((recent_ms or 0) / 1000)
  local best_path, best_mtime = nil, nil
  while true do
    local name, entry_type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if entry_type == 'file' and name:match '%.jsonl$' then
      local path = dir .. '/' .. name
      local stat = vim.uv.fs_stat(path)
      if stat and stat.mtime and stat.mtime.sec >= cutoff then
        if not best_mtime or stat.mtime.sec > best_mtime then
          best_mtime = stat.mtime.sec
          best_path = path
        end
      end
    end
  end
  return best_path
end

---@param callback function(table|nil)
---@param status_callback function(string)|nil
function M.get_recent(callback, status_callback)
  local logger = log()
  if config.values.context and config.values.context.claude == false then
    logger.debug 'Claude Code context disabled'
    callback(nil)
    return
  end

  local opts = config.values.claude_context or {}
  local projects_dir = opts.projects_dir
  if type(projects_dir) ~= 'string' or projects_dir == '' then
    logger.debug 'Claude Code projects dir not configured'
    callback(nil)
    return
  end

  local cwd = vim.fn.getcwd()
  local session_dir = projects_dir .. '/' .. encode_project_dir(cwd)
  local dir_stat = vim.uv.fs_stat(session_dir)
  if not dir_stat or dir_stat.type ~= 'directory' then
    logger.debug('Claude Code project dir unavailable: ' .. session_dir)
    callback(nil)
    return
  end

  if status_callback then
    status_callback 'Claude Code: Loading session context'
  end

  logger.debug('Looking for recent Claude Code session (cwd=' .. cwd .. ' dir=' .. session_dir .. ')')
  local session_file = find_recent_session_file(session_dir, opts.recent_ms or 60 * 60 * 1000)
  if not session_file then
    logger.debug('No recent Claude Code session found in ' .. session_dir)
    callback(nil)
    return
  end

  local ok, lines = pcall(vim.fn.readfile, session_file)
  if not ok or type(lines) ~= 'table' then
    logger.debug('Failed to read Claude Code session file: ' .. session_file)
    callback(nil)
    return
  end

  local entries = parse_entries(lines)
  local transcript = build_transcript(entries)
  if not transcript then
    logger.debug('Claude Code session had no transcript after filtering: ' .. session_file)
    callback(nil)
    return
  end

  local title = session_file:match '([^/]+)%.jsonl$' or session_file
  logger.debug(string.format('Claude Code session context ready (file=%s transcript_chars=%d)', session_file, #transcript))
  callback {
    provider = 'claude',
    label = 'Claude Code',
    title = title,
    directory = cwd,
    transcript = transcript,
  }
end

return M
