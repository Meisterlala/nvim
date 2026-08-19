local config = require 'ai-commit.config'
local log = require('ai-commit.log').get
local parser = require 'ai-commit.session_context.pi_parser'

local M = {}

---@param path string
---@return string
local function normalize_path(path)
  local normalized = vim.fs.normalize(vim.fn.expand(path))
  return vim.uv.fs_realpath(normalized) or normalized
end

---@param stat table|nil
---@return integer|nil
local function mtime_ms(stat)
  if not stat or not stat.mtime or not stat.mtime.sec then
    return nil
  end
  return (stat.mtime.sec * 1000) + math.floor((stat.mtime.nsec or 0) / 1000000)
end

---@param opts table
---@return string
local function sessions_dir(opts)
  if type(opts.sessions_dir) == 'string' and opts.sessions_dir ~= '' then
    return normalize_path(opts.sessions_dir)
  end

  local session_dir = vim.env.PI_CODING_AGENT_SESSION_DIR
  if type(session_dir) == 'string' and session_dir ~= '' then
    return normalize_path(session_dir)
  end

  local agent_dir = vim.env.PI_CODING_AGENT_DIR
  if type(agent_dir) == 'string' and agent_dir ~= '' then
    return normalize_path(agent_dir .. '/sessions')
  end

  return normalize_path '~/.pi/agent/sessions'
end

---@param path string
---@param candidates table[]
---@param seen table<string, boolean>
local function add_candidate(path, candidates, seen)
  path = normalize_path(path)
  if seen[path] or not path:match '%.jsonl$' then
    return
  end
  local stat = vim.uv.fs_stat(path)
  local updated_at = mtime_ms(stat)
  if not updated_at or not stat or stat.type ~= 'file' then
    return
  end
  seen[path] = true
  table.insert(candidates, { path = path, updated_at = updated_at })
end

---@param dir string
---@param depth integer
---@param candidates table[]
---@param seen table<string, boolean>
local function scan_dir(dir, depth, candidates, seen)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return
  end

  while true do
    local name, entry_type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local path = dir .. '/' .. name
    if entry_type == 'file' then
      add_candidate(path, candidates, seen)
    elseif entry_type == 'directory' and depth > 0 then
      scan_dir(path, depth - 1, candidates, seen)
    end
  end
end

---@param candidate table
---@param cwd string
---@param opts table
---@param cutoff_ms integer
---@return table|nil
local function load_candidate(candidate, cwd, opts, cutoff_ms)
  if candidate.updated_at < cutoff_ms then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, candidate.path)
  if not ok or type(lines) ~= 'table' then
    return nil
  end

  local parsed = parser.parse(lines, opts)
  if not parsed or normalize_path(parsed.cwd) ~= cwd then
    return nil
  end

  return {
    provider = 'pi',
    label = 'Pi',
    title = parsed.title or parsed.id or candidate.path,
    directory = parsed.cwd,
    transcript = parsed.transcript,
    updated_at = candidate.updated_at,
    session_file = candidate.path,
  }
end

---@param callback function(table|nil)
---@param status_callback function(string)|nil
function M.get_recent(callback, status_callback)
  local logger = log()
  if config.values.context and config.values.context.pi == false then
    logger.debug 'Pi context disabled'
    callback(nil)
    return
  end

  local opts = config.values.pi_context or {}
  local cwd = normalize_path(vim.fn.getcwd())
  local recent_ms = opts.recent_ms or 60 * 60 * 1000
  local cutoff_ms = math.floor(os.time() * 1000) - recent_ms
  local seen = {}

  if status_callback then
    status_callback 'Pi: Loading session context'
  end

  local session_file = vim.env.PI_SESSION_FILE
  if type(session_file) == 'string' and session_file ~= '' then
    local candidates = {}
    add_candidate(session_file, candidates, seen)
    if candidates[1] then
      local session = load_candidate(candidates[1], cwd, opts, cutoff_ms)
      if session then
        logger.debug(string.format('Pi session context ready from environment (file=%s transcript_chars=%d)', session.session_file, #session.transcript))
        callback(session)
        return
      end
    end
  end

  local root = sessions_dir(opts)
  local candidates = {}
  scan_dir(root, 1, candidates, seen)
  table.sort(candidates, function(left, right)
    return left.updated_at > right.updated_at
  end)

  logger.debug(string.format('Looking for recent Pi session (cwd=%s root=%s candidates=%d)', cwd, root, #candidates))
  for _, candidate in ipairs(candidates) do
    if candidate.updated_at < cutoff_ms then
      break
    end
    local session = load_candidate(candidate, cwd, opts, cutoff_ms)
    if session then
      logger.debug(string.format('Pi session context ready (file=%s transcript_chars=%d)', session.session_file, #session.transcript))
      callback(session)
      return
    end
  end

  logger.debug('No recent Pi session found for cwd=' .. cwd)
  callback(nil)
end

return M
