local config = require 'ai-commit.config'
local log = require('ai-commit.log').get
local state = require 'ai-commit.state'

local M = {}

local frames = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local DEFAULT_MAX_PREVIEW_CHARS = 4000

local function preview_width(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  if win ~= -1 then
    return math.max(20, vim.api.nvim_win_get_width(win) - 4)
  end
  return 76
end

local function split_long_token(token, width)
  local parts = {}
  local current = ''
  local index = 0
  local length = vim.fn.strchars(token)

  while index < length do
    local char = vim.fn.strcharpart(token, index, 1)
    if current ~= '' and vim.fn.strdisplaywidth(current .. char) > width then
      table.insert(parts, current)
      current = char
    else
      current = current .. char
    end
    index = index + 1
  end

  if current ~= '' then
    table.insert(parts, current)
  end
  return parts
end

local function tail_text(text, max_chars)
  local length = vim.fn.strchars(text)
  if length <= max_chars then
    return text
  end
  return vim.fn.strcharpart(text, length - max_chars, max_chars)
end

local function wrap_line(line, width)
  line = tail_text(line, math.max(width * (config.values.preview_lines or 5) * 2, width))
  if line == '' or vim.fn.strdisplaywidth(line) <= width then
    return { line }
  end

  local wrapped = {}
  local indent = line:match '^%s*' or ''
  local content = line:sub(#indent + 1)
  local current = indent
  local continuation_indent = indent ~= '' and indent or '  '

  for token in content:gmatch '%S+%s*' do
    local candidate = current .. token
    if current:match '%S' and vim.fn.strdisplaywidth(candidate) > width then
      table.insert(wrapped, (current:gsub('%s+$', '')))
      current = continuation_indent .. token
    else
      current = candidate
    end

    if vim.fn.strdisplaywidth(current) > width then
      local parts = split_long_token(current:gsub('%s+$', ''), width)
      for index, part in ipairs(parts) do
        if index < #parts then
          table.insert(wrapped, part)
        else
          current = continuation_indent .. part:gsub('^%s+', '')
        end
      end
    end
  end

  if current ~= '' then
    table.insert(wrapped, (current:gsub('%s+$', '')))
  end
  return #wrapped > 0 and wrapped or { line }
end

local function stop_timer_safe(spinner)
  local timer = spinner and spinner.timer
  if not timer then
    return
  end
  spinner.timer = nil
  pcall(function()
    if timer.stop then
      timer:stop()
    end
  end)
  pcall(function()
    if timer.close then
      timer:close()
    end
  end)
end

---@param spinner table
---@param bufnr integer
---@return table
local function preview_virt_lines(spinner, bufnr)
  local lines = {}
  local width = preview_width(bufnr)
  local preview_lines = config.values.preview_lines or 5
  local start = math.max(1, #spinner.stream_preview - preview_lines - 2)
  for index = start, #spinner.stream_preview do
    local line = spinner.stream_preview[index]
    for _, wrapped in ipairs(wrap_line(line, width)) do
      table.insert(lines, wrapped)
    end
  end

  while #lines > preview_lines do
    table.remove(lines, 1)
  end

  local virt_lines = {}
  for _, line in ipairs(lines) do
    table.insert(virt_lines, { { line, 'Comment' } })
  end
  return virt_lines
end

---@param bufnr integer
---@return table
function M.start(bufnr)
  local logger = log()
  logger.debug('Starting spinner for buffer ' .. bufnr)

  local spinner = {
    timer = nil,
    extmark_id = nil,
    status_text = 'Preparing commit message',
    status_chunks = { { 'Preparing commit message', 'Comment' } },
    stream_preview = {},
    stop_timer = stop_timer_safe,
  }

  local frame_idx = 1
  local function update()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      stop_timer_safe(spinner)
      return
    end

    local row, col = 0, 0
    if spinner.extmark_id then
      local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, state.ns_id, spinner.extmark_id, {})
      if pos and #pos >= 2 then
        row, col = pos[1], pos[2]
      end
    end

    local virt_text = { { frames[frame_idx] .. ' ', 'Comment' } }
    if spinner.status_chunks and #spinner.status_chunks > 0 then
      vim.list_extend(virt_text, spinner.status_chunks)
    else
      table.insert(virt_text, { spinner.status_text, 'Comment' })
    end

    local opts = {
      id = spinner.extmark_id,
      right_gravity = false,
      virt_text = virt_text,
      virt_text_pos = 'eol',
    }
    local virt_lines = preview_virt_lines(spinner, bufnr)
    if #virt_lines > 0 then
      opts.virt_lines = virt_lines
      opts.virt_lines_above = false
    end
    spinner.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, row, col, opts)
    frame_idx = (frame_idx % #frames) + 1
  end

  update()
  local timer = vim.uv.new_timer()
  if timer then
    timer:start(config.values.spinner_interval, config.values.spinner_interval, vim.schedule_wrap(update))
  end
  spinner.timer = timer
  spinner.update = update
  return spinner
end

---@param spinner table|nil
---@param text string
function M.append_stream(spinner, text)
  if not spinner or not text or text == '' then
    return
  end
  if vim.in_fast_event() then
    vim.schedule(function()
      M.append_stream(spinner, text)
    end)
    return
  end

  local chunks = vim.split(text, '\n', { plain = true })
  for index, chunk in ipairs(chunks) do
    if index > 1 then
      table.insert(spinner.stream_preview, '')
    elseif #spinner.stream_preview == 0 then
      table.insert(spinner.stream_preview, '')
    end
    spinner.stream_preview[#spinner.stream_preview] = (spinner.stream_preview[#spinner.stream_preview] or '') .. chunk
  end

  while #spinner.stream_preview > 200 do
    table.remove(spinner.stream_preview, 1)
  end

  local max_chars = config.values.preview_max_chars or DEFAULT_MAX_PREVIEW_CHARS
  local total = 0
  for index = #spinner.stream_preview, 1, -1 do
    local line = spinner.stream_preview[index]
    total = total + vim.fn.strchars(line)
    if total > max_chars then
      local keep = math.max(0, max_chars - (total - vim.fn.strchars(line)))
      if keep > 0 then
        spinner.stream_preview[index] = tail_text(line, keep)
      else
        table.remove(spinner.stream_preview, index)
      end
      for remove_index = index - 1, 1, -1 do
        table.remove(spinner.stream_preview, remove_index)
      end
      break
    end
  end
end

---@param spinner table|nil
function M.start_stream_section(spinner)
  if not spinner or #spinner.stream_preview == 0 then
    return
  end

  if spinner.stream_preview[#spinner.stream_preview] ~= '' then
    table.insert(spinner.stream_preview, '')
  end
end

---@param spinner table|nil
---@param status_text string
---@param status_chunks table|nil
function M.set_status(spinner, status_text, status_chunks)
  if not spinner then
    return
  end
  spinner.status_text = status_text
  spinner.status_chunks = status_chunks
end

---@param bufnr integer
---@param spinner table
---@return integer
function M.stop(bufnr, spinner)
  local insert_row = 0
  if spinner and spinner.stop_timer then
    spinner.stop_timer(spinner)
  end
  if vim.api.nvim_buf_is_valid(bufnr) and spinner and spinner.extmark_id then
    local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, state.ns_id, spinner.extmark_id, {})
    if pos and #pos >= 1 then
      insert_row = pos[1]
    end
    vim.api.nvim_buf_del_extmark(bufnr, state.ns_id, spinner.extmark_id)
  end
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, state.ns_id, 0, -1)
  end
  return insert_row
end

return M
