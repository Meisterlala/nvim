local M = {}

local DEFAULT_TIMEOUT = 30000

local function schedule(callback, ...)
  local args = { ... }
  vim.schedule(function()
    callback(unpack(args))
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
---@field callback fun(code: integer, error: string|nil) Called when curl exits.

---Run a streaming curl request and decode each stdout line as JSON.
---@param request AiProviderCurlStreamRequest
---@return table job Plenary job handle.
function M.stream_json_lines(request)
  local Job = require 'plenary.job'
  local body = encode_body(request.body)
  local method = request.method or 'POST'
  local timeout = request.timeout or DEFAULT_TIMEOUT
  local args = {
    '--silent',
    '--show-error',
    '--no-buffer',
    '--max-time',
    tostring(math.ceil(timeout / 1000)),
    '--request',
    method,
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
  local job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, line)
      if not line or line == '' or (request.is_cancelled and request.is_cancelled()) then
        return
      end

      local ok, data = pcall(vim.json.decode, line)
      if not ok or type(data) ~= 'table' then
        return
      end

      if request.on_json_line then
        request.on_json_line(data, line)
      end
    end,
    on_stderr = function(_, line)
      if line and line ~= '' then
        table.insert(stderr, line)
      end
    end,
    on_exit = function(_, code)
      schedule(request.callback, code, #stderr > 0 and table.concat(stderr, '\n') or nil)
    end,
  }

  job:start()
  return job
end

return M
