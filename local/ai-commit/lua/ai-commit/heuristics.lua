local M = {}

local DESCRIPTION_TARGET_MAX = 100
local DESCRIPTION_HARD_MAX = 120
local BODY_MAX = 80
local BODY_CHAR_HARD_MAX = 800
local BODY_LINE_HARD_MAX = 8

local function valid_footer(line)
  if line:match '^BREAKING CHANGE: .+$' then
    return true
  end
  return line:match '^[A-Za-z0-9-]+: .+$' ~= nil or line:match '^[A-Za-z0-9-]+ #%S.*$' ~= nil
end

local function looks_like_footer(line)
  return line:match '^[A-Z][A-Z ]*: ?' ~= nil or line:match '^[A-Za-z0-9-]+[:#]' ~= nil or line:match '^[A-Za-z0-9-]+ #%S*' ~= nil
end

local function wrap_line(line, limit)
  if #line <= limit or line:match '^%s*$' then
    return { line }
  end

  local wrapped = {}
  local current = ''
  for word in line:gmatch '%S+' do
    if current == '' then
      current = word
    elseif #current + 1 + #word <= limit then
      current = current .. ' ' .. word
    else
      table.insert(wrapped, current)
      current = word
    end
  end
  if current ~= '' then
    table.insert(wrapped, current)
  end
  return wrapped
end

local function split_one_line_message(message)
  local prefix, description = message:match '^([^:]+: )(.+)$'
  if not prefix or not description or #description <= DESCRIPTION_HARD_MAX then
    return message
  end

  local first_sentence, rest = description:match '^([^%.]+)%.%s+(.+)$'
  if not first_sentence or not rest then
    return message
  end

  return prefix .. first_sentence:gsub('%s+$', '') .. '\n\n' .. rest:gsub('%.%s*$', '')
end

local function parse_first_line(first_line)
  local prefix, description = first_line:match '^([^:]+): (.+)$'
  if not prefix or not description then
    return nil
  end

  local type_name, scope = prefix:match '^([a-z][a-z0-9-]*)%(([a-zA-Z0-9_.-]+)%)!?$'
  if type_name and scope then
    return { prefix = prefix, description = description }
  end

  type_name = prefix:match '^([a-z][a-z0-9-]*)!?$'
  if type_name then
    return { prefix = prefix, description = description }
  end

  return nil
end

---@param failures string[]
---@param warnings string[]
---@param message string
---@param max_body integer
local function check_lines(failures, warnings, message, max_body)
  local lines = vim.split(message or '', '\n', { plain = true })
  local first_line = lines[1] or ''
  local parsed_first_line = parse_first_line(first_line)
  local first_line_has_breaking_marker = first_line:match '^[^:]+!:' ~= nil
  local has_breaking_footer = false

  if first_line == '' then
    table.insert(failures, 'missing first line with <type>[optional scope]: <description>')
  elseif not parsed_first_line then
    table.insert(failures, 'first line must match Conventional Commits: <type>[optional scope][optional !]: <description>')
  end

  if parsed_first_line then
    local description = parsed_first_line.description
    local description_length_message = string.format('description is %d chars; max is %d', #description, DESCRIPTION_TARGET_MAX)
    if #description > DESCRIPTION_HARD_MAX then
      table.insert(failures, description_length_message)
    elseif #description > DESCRIPTION_TARGET_MAX then
      table.insert(warnings, description_length_message)
    end

    if description:match 'BREAKING CHANGE' then
      table.insert(failures, 'BREAKING CHANGE must be a separate footer, not part of the description')
    end
    if #description <= DESCRIPTION_HARD_MAX then
      if description:match '%.$' then
        table.insert(failures, 'description must not end with a period')
      end
      if description:match '^%u' then
        table.insert(failures, 'description should start lowercase')
      end
    end
  end

  if #lines > 1 then
    if lines[2] ~= '' then
      table.insert(failures, 'body or footer(s) must be separated from the first line by one blank line')
    end
    if #lines == 2 then
      table.insert(failures, 'message must not end with a dangling blank line')
    end
    if lines[3] == '' then
      table.insert(failures, 'message must not contain multiple blank lines after the first line')
    end
  end

  local blank_run = 0
  local possible_footer_block = #lines > 2 and lines[2] == ''
  local body_chars = 0
  local body_lines = 0
  local in_footer = false
  for idx = 3, #lines do
    local line = lines[idx]
    if #line > max_body then
      table.insert(failures, string.format('line %d is %d chars; max is %d', idx, #line, max_body))
    end
    if line == '' then
      blank_run = blank_run + 1
      if blank_run > 1 then
        table.insert(failures, 'message must not contain repeated blank lines')
      end
      possible_footer_block = true
    else
      blank_run = 0
      if possible_footer_block and valid_footer(line) then
        in_footer = true
        if line:match '^BREAKING CHANGE: ' then
          has_breaking_footer = true
        end
        possible_footer_block = true
      elseif possible_footer_block and looks_like_footer(line) then
        table.insert(failures, string.format('line %d looks like an invalid footer', idx))
        possible_footer_block = false
      else
        possible_footer_block = false
      end
      if line:match '^%s*[-*+]%s+' then
        table.insert(failures, string.format('line %d must not use markdown list formatting', idx))
      end
      if not in_footer then
        body_chars = body_chars + #line
        body_lines = body_lines + 1
      end
    end
  end
  if body_chars > BODY_CHAR_HARD_MAX then
    table.insert(failures, string.format('body is %d chars; max is %d', body_chars, BODY_CHAR_HARD_MAX))
  end
  if body_lines > BODY_LINE_HARD_MAX then
    table.insert(failures, string.format('body is %d lines; max is %d', body_lines, BODY_LINE_HARD_MAX))
  end
  if first_line_has_breaking_marker and not has_breaking_footer and #lines == 1 then
    table.insert(warnings, 'breaking-change marker used without body or BREAKING CHANGE footer')
  end
end

---@param message string|nil
---@return table
function M.validate(message)
  local failures = {}
  local warnings = {}
  if type(message) ~= 'string' or message:match '^%s*$' then
    return { valid = false, failures = { 'message is empty' }, warnings = warnings }
  end

  if message:find '```' then
    table.insert(failures, 'message must not include markdown code fences')
  end
  if message:find '^%s' or message:find '%s$' then
    table.insert(failures, 'message must not have leading or trailing whitespace')
  end

  check_lines(failures, warnings, message, BODY_MAX)
  return { valid = #failures == 0, failures = failures, warnings = warnings }
end

---@param message string|nil
---@return string|nil
function M.normalize(message)
  if type(message) ~= 'string' then
    return nil
  end

  local trimmed = vim.trim(message)
  if not trimmed:find('\n', 1, true) then
    trimmed = split_one_line_message(trimmed)
  end

  local lines = vim.split(trimmed, '\n', { plain = true })
  lines[1] = (lines[1] or ''):gsub('%.%s*$', '')
  if #lines <= 2 then
    return table.concat(lines, '\n')
  end

  local normalized = { lines[1], lines[2] }
  if #lines == 3 then
    local line = lines[3]:gsub('^%s*[-*+]%s+', '')
    for _, wrapped in ipairs(wrap_line(line, BODY_MAX)) do
      table.insert(normalized, wrapped)
    end
    return table.concat(normalized, '\n')
  end

  for idx = 3, #lines do
    local line = lines[idx]:gsub('^%s*[-*+]%s+', '')
    table.insert(normalized, line)
  end

  return table.concat(normalized, '\n')
end

---@param result table
---@return string
function M.format_failures(result)
  if not result or not result.failures or #result.failures == 0 then
    return 'No heuristic failures.'
  end

  local lines = {}
  for _, failure in ipairs(result.failures) do
    table.insert(lines, '- ' .. failure)
  end
  for _, warning in ipairs(result.warnings or {}) do
    table.insert(lines, '- warning: ' .. warning)
  end
  return table.concat(lines, '\n')
end

return M
