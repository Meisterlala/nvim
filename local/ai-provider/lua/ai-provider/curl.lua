local M = {}

local DEFAULT_TIMEOUT = 30000

local function unpack_values(values, index, last)
  if index > last then
    return
  end
  return values[index], unpack_values(values, index + 1, last)
end

local function schedule(callback, ...)
  local args = { n = select('#', ...), ... }
  vim.schedule(function()
    callback(unpack_values(args, 1, args.n))
  end)
end

local function encode_body(body)
  if type(body) == 'string' then
    return body
  end
  if body ~= nil then
    return vim.json.encode(body)
  end
  return nil
end

local function json_headers(headers)
  headers = vim.tbl_extend('force', {}, headers or {})
  headers['Content-Type'] = headers['Content-Type'] or 'application/json'
  return headers
end

---@class AiProviderCurlResponse
---@field status integer HTTP status code. `0` means curl/plenary failed before HTTP response parsing.
---@field body string Raw response body.
---@field json table|nil Decoded JSON body when decoding succeeded.
---@field error string|nil Transport or decode error message.

---@class AiProviderCurlRequest
---@field method? string HTTP method. Defaults to `GET`.
---@field url string Request URL.
---@field headers? table<string, string> HTTP headers.
---@field body? table|string Request body. Tables are JSON encoded.
---@field timeout? integer Request timeout in milliseconds.
---@field callback fun(response: AiProviderCurlResponse) Completion callback.

---Run a non-streaming HTTP request and decode JSON responses when possible.
---@param request AiProviderCurlRequest
function M.json(request)
  local curl = require 'plenary.curl'
  local method = string.lower(request.method or 'GET')
  local body = encode_body(request.body)

  local opts = {
    headers = json_headers(request.headers),
    body = body,
    timeout = request.timeout or DEFAULT_TIMEOUT,
    callback = function(response)
      local decoded = nil
      if type(response.body) == 'string' and response.body ~= '' then
        local ok, data = pcall(vim.json.decode, response.body)
        if ok then
          decoded = data
        end
      end

      schedule(request.callback, {
        status = response.status or 0,
        body = response.body or '',
        json = decoded,
      })
    end,
    on_error = function(err)
      schedule(request.callback, {
        status = 0,
        body = '',
        error = tostring(err and (err.stderr or err.message) or 'curl request failed'),
      })
    end,
  }

  if method == 'post' then
    return curl.post(request.url, opts)
  elseif method == 'put' then
    return curl.put(request.url, opts)
  elseif method == 'delete' then
    return curl.delete(request.url, opts)
  end

  return curl.get(request.url, opts)
end

---@class AiProviderCurlStreamRequest
---@field method? string HTTP method. Defaults to `POST`.
---@field url string Request URL.
---@field headers? table<string, string> HTTP headers.
---@field body? table|string Request body. Tables are JSON encoded.
---@field timeout? integer Curl max-time in milliseconds.
---@field is_cancelled? fun(): boolean Optional cancellation predicate.
---@field on_json_line? fun(data: table, line: string) Called for each decoded JSON line.
---@field callback fun(code: integer, error: string|nil, status: integer|nil) Called when curl exits.

---Run a streaming curl request and decode each stdout line as JSON.
---@param request AiProviderCurlStreamRequest
---@return table job Plenary job handle.
function M.stream_json_lines(request)
  local Job = require 'plenary.job'
  local body = encode_body(request.body)
  local method = request.method or 'POST'
  local timeout = request.timeout or DEFAULT_TIMEOUT
  local status_marker = '__AI_PROVIDER_HTTP_STATUS__:'
  local args = {
    '--silent',
    '--show-error',
    '--no-buffer',
    '--max-time',
    tostring(math.ceil(timeout / 1000)),
    '--request',
    method,
    '--write-out',
    '\n' .. status_marker .. '%{http_code}',
  }

  for name, value in pairs(json_headers(request.headers)) do
    table.insert(args, '--header')
    table.insert(args, name .. ': ' .. value)
  end

  if body then
    table.insert(args, '--data')
    table.insert(args, body)
  end

  table.insert(args, request.url)

  local stderr = {}
  local stdout_lines = {}
  local http_status = nil
  local stdout_buffer = ''

  local function process_stdout_line(line)
    line = line:gsub('^%s+', ''):gsub('%s+$', '')
    if line == '' then
      return
    end

    local status = line:match('^' .. status_marker .. '(%d+)$')
    if status then
      http_status = tonumber(status)
      return
    end

    local payload = line
    local event_data = line:match '^data:%s*(.*)$'
    if event_data then
      if event_data == '[DONE]' then
        return
      end
      payload = event_data
    end

    if #stdout_lines < 20 then
      table.insert(stdout_lines, payload)
    end

    local ok, data = pcall(vim.json.decode, payload)
    if ok and type(data) == 'table' and request.on_json_line then
      schedule(request.on_json_line, data, line)
    end
  end

  local job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, output)
      if not output or output == '' or (request.is_cancelled and request.is_cancelled()) then
        return
      end

      local text = tostring(output)
      if stdout_buffer == '' and not text:find('[\r\n]') then
        process_stdout_line(text)
        return
      end

      stdout_buffer = stdout_buffer .. text
      while true do
        local newline_at = stdout_buffer:find('[\r\n]')
        if not newline_at then
          break
        end

        process_stdout_line(stdout_buffer:sub(1, newline_at - 1))
        stdout_buffer = stdout_buffer:sub(newline_at + 1)
      end
    end,
    on_stderr = function(_, line)
      if line and line ~= '' then
        table.insert(stderr, line)
      end
    end,
    on_exit = function(_, code)
      if stdout_buffer ~= '' and not (request.is_cancelled and request.is_cancelled()) then
        process_stdout_line(stdout_buffer)
        stdout_buffer = ''
      end

      local error_parts = {}
      if #stderr > 0 then
        table.insert(error_parts, table.concat(stderr, '\n'))
      end
      if http_status and http_status >= 400 and #stdout_lines > 0 then
        table.insert(error_parts, table.concat(stdout_lines, '\n'))
      end
      schedule(request.callback, code, #error_parts > 0 and table.concat(error_parts, '\n') or nil, http_status)
    end,
  }

  job:start()
  return job
end

return M
