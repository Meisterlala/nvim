local config = require 'ai-commit.config'
local log = require('ai-commit.log').get
local util = require 'ai-commit.util'

local M = {}

---@param value string
---@return string
local function sql_quote(value)
  return "'" .. tostring(value):gsub("'", "''") .. "'"
end

---@param message table
---@return string
local function message_text(message)
  local parts = {}
  for _, part in ipairs(message.parts or {}) do
    if type(part) == 'string' and part ~= '' then
      table.insert(parts, part)
    end
  end
  return util.strip_relevant_memories(table.concat(parts, '\n'))
end

---@param messages table[]
---@return string|nil
local function build_transcript(messages)
  local logger = log()
  local opts = config.values.opencode_context or {}
  local max_message_chars = opts.max_message_chars or 5000
  local max_transcript_chars = opts.max_transcript_chars or 30000
  local assistant_limit = opts.assistant_messages or 4

  local first_user = nil
  local last_user = nil
  local assistants = {}

  for _, message in ipairs(messages) do
    local text = message_text(message)
    if text ~= '' then
      if message.role == 'user' then
        first_user = first_user or message
        last_user = message
      elseif message.role == 'assistant' then
        table.insert(assistants, message)
      end
    end
  end

  local selected = {}
  if first_user then
    table.insert(selected, { label = 'Initial user message', message = first_user })
  end
  if last_user and last_user ~= first_user then
    table.insert(selected, { label = 'Latest user message', message = last_user })
  end

  for index = math.max(1, #assistants - assistant_limit + 1), #assistants do
    table.insert(selected, { label = 'Recent assistant response', message = assistants[index] })
  end

  if #selected == 0 then
    logger.debug('OpenCode transcript selection found no usable messages (messages=' .. tostring(#messages) .. ')')
    return nil
  end

  local lines = {}
  for _, item in ipairs(selected) do
    local text = util.truncate_text(message_text(item.message), max_message_chars)
    table.insert(lines, string.format('%s (%s):\n%s', item.label, item.message.role or 'unknown', text))
  end

  local transcript = util.truncate_text(table.concat(lines, '\n\n---\n\n'), max_transcript_chars)
  logger.debug(
    string.format(
      'OpenCode transcript built (messages=%d users=%s assistants=%d selected=%d chars=%d)',
      #messages,
      first_user and 'yes' or 'no',
      #assistants,
      #selected,
      #transcript
    )
  )
  return transcript
end

---@param rows table[]
---@return table[]
local function parse_messages(rows)
  local logger = log()
  local messages = {}
  local by_id = {}
  local text_parts = 0

  for _, row in ipairs(rows) do
    local message = by_id[row.message_id]
    if not message then
      local ok, message_data = pcall(vim.json.decode, row.message_data or '{}')
      if not ok or type(message_data) ~= 'table' then
        message_data = {}
      end
      message = {
        id = row.message_id,
        role = message_data.role,
        time_created = row.message_time,
        parts = {},
      }
      by_id[row.message_id] = message
      table.insert(messages, message)
    end

    if row.part_data then
      local ok, part_data = pcall(vim.json.decode, row.part_data)
      if ok and type(part_data) == 'table' and part_data.type == 'text' and type(part_data.text) == 'string' then
        table.insert(message.parts, part_data.text)
        text_parts = text_parts + 1
      end
    end
  end

  logger.debug(string.format('OpenCode parsed messages (rows=%d messages=%d text_parts=%d)', #rows, #messages, text_parts))
  return messages
end

---@param db_path string
---@param session table
---@param callback function(table|nil)
---@param status_callback function(string)|nil
local function read_session_messages(db_path, session, callback, status_callback)
  local logger = log()
  local Job = require 'plenary.job'
  if status_callback then
    status_callback 'Reading OpenCode session'
  end
  logger.debug('Reading OpenCode session messages for session=' .. tostring(session.id))
  local sql = table.concat({
    'select m.id as message_id, m.time_created as message_time, m.data as message_data,',
    'p.id as part_id, p.time_created as part_time, p.data as part_data',
    'from message m left join part p on p.message_id = m.id',
    'where m.session_id = ' .. sql_quote(session.id),
    'order by m.time_created asc, p.time_created asc, p.id asc;',
  }, ' ')

  Job:new({
    command = 'sqlite3',
    args = { '-json', db_path, sql },
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        logger.debug('OpenCode message lookup failed: ' .. table.concat(job:stderr_result(), '\n'))
        callback(nil)
        return
      end

      local ok, rows = pcall(vim.json.decode, table.concat(job:result(), '\n'))
      if not ok or type(rows) ~= 'table' then
        logger.debug('OpenCode message lookup returned invalid JSON for session=' .. tostring(session.id))
        callback(nil)
        return
      end

      local transcript = build_transcript(parse_messages(rows))
      if not transcript then
        logger.debug('OpenCode session had no transcript after filtering session=' .. tostring(session.id))
        callback(nil)
        return
      end

      logger.debug(
        string.format('OpenCode session context ready (session=%s title=%s transcript_chars=%d)', tostring(session.id), tostring(session.title), #transcript)
      )
      callback {
        provider = 'opencode',
        label = 'OpenCode',
        title = session.title or session.id,
        directory = session.directory or vim.fn.getcwd(),
        transcript = transcript,
      }
    end),
  }):start()
end

---@param callback function(table|nil)
---@param status_callback function(string)|nil
function M.get_recent(callback, status_callback)
  local opts = config.values.opencode_context or {}
  local logger = log()
  if config.values.context and config.values.context.opencode == false then
    logger.debug 'OpenCode context disabled'
    callback(nil)
    return
  end

  local db_path = opts.db_path
  if type(db_path) ~= 'string' or db_path == '' or not vim.uv.fs_stat(db_path) then
    logger.debug('OpenCode context DB unavailable: ' .. tostring(db_path))
    callback(nil)
    return
  end

  local Job = require 'plenary.job'
  local cwd = vim.fn.getcwd()
  local since_ms = math.floor(os.time() * 1000) - (opts.recent_ms or 60 * 60 * 1000)
  if status_callback then
    status_callback 'Inspecting OpenCode session'
  end
  logger.debug(
    string.format('Looking for recent OpenCode session (cwd=%s db=%s recent_ms=%s since_ms=%s)', cwd, db_path, tostring(opts.recent_ms), tostring(since_ms))
  )
  local sql = table.concat({
    'select id, title, directory, time_updated from session',
    'where directory = ' .. sql_quote(cwd),
    'and time_updated >= ' .. tostring(since_ms),
    'order by time_updated desc limit 1;',
  }, ' ')

  Job:new({
    command = 'sqlite3',
    args = { '-json', db_path, sql },
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        logger.debug('OpenCode session lookup failed: ' .. table.concat(job:stderr_result(), '\n'))
        callback(nil)
        return
      end

      local ok, sessions = pcall(vim.json.decode, table.concat(job:result(), '\n'))
      if not ok or type(sessions) ~= 'table' or not sessions[1] then
        logger.debug('No recent OpenCode session found for cwd=' .. cwd)
        callback(nil)
        return
      end

      logger.debug(
        string.format(
          'Recent OpenCode session found (id=%s title=%s updated=%s)',
          tostring(sessions[1].id),
          tostring(sessions[1].title),
          tostring(sessions[1].time_updated)
        )
      )
      read_session_messages(db_path, sessions[1], callback, status_callback)
    end),
  }):start()
end

return M
