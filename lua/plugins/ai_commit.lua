--- AI-powered Git commit message generator using GitHub Copilot

-- Configuration - Change these to customize behavior
local CONFIG = {
  -- Use :AICommitModels to select a model
  model = nil, -- nil = auto (use Copilot's default)
  model_name = nil, -- Friendly display name for selected model

  temperature = 0.3, -- Lower = more focused, higher = more creative
  max_tokens = 1000, -- Max length of generated message
  spinner_interval = 80, -- Spinner animation speed (ms)
  max_diff_chars = 100000, -- Truncate very large diffs before sending to model
  chat_timeout = 30000, -- Chat completion timeout (ms)
  model_highlight_group = 'Special', -- Highlight group for model name in spinner status

  log_level = 'warn',
}

-- Constants
local COPILOT_AUTH_URL = 'https://api.github.com/copilot_internal/v2/token'
local COPILOT_API_ENDPOINT = 'https://api.githubcopilot.com'
local SPINNER_FRAMES = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

local COMMIT_PROMPT_TEMPLATE = [[You are a git commit message generator following Conventional Commits v1.0.0 specification.

STRUCTURE:
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]

SPECIFICATION (https://www.conventionalcommits.org/en/v1.0.0/):

1. Commits MUST be prefixed with a type, which consists of a noun, feat, fix, etc., followed by the OPTIONAL scope, OPTIONAL !, and REQUIRED terminal colon and space.
2. The type feat MUST be used when a commit adds a new feature to your application or library.
3. The type fix MUST be used when a commit represents a bug fix for your application.
4. A scope MAY be provided after a type. A scope MUST consist of a noun describing a section of the codebase surrounded by parenthesis, e.g., fix(parser):
5. A description MUST immediately follow the colon and space after the type/scope prefix. The description is a short summary of the code changes, e.g., fix: array parsing issue when multiple spaces were contained in string.
6. A longer commit body MAY be provided after the short description, providing additional contextual information about the code changes. The body MUST begin one blank line after the description.
7. A commit body is free-form and MAY consist of any number of newline separated paragraphs.
8. One or more footers MAY be provided one blank line after the body. Each footer MUST consist of a word token, followed by either a :<space> or <space># separator, followed by a string value (this is inspired by the git trailer convention).
9. A footer's token MUST use - in place of whitespace characters, e.g., Acked-by (this helps differentiate the footer section from a multi-paragraph body). An exception is made for BREAKING CHANGE, which MAY also be used as a token.
10. A footer's value MAY contain spaces and newlines, and parsing MUST terminate when the next valid footer token/separator pair is observed.
11. Breaking changes MUST be indicated in the type/scope prefix of a commit, or as an entry in the footer.
12. If included as a footer, a breaking change MUST consist of the uppercase text BREAKING CHANGE, followed by a colon, space, and description, e.g., BREAKING CHANGE: environment variables now take precedence over config files.
13. If included in the type/scope prefix, breaking changes MUST be indicated by a ! immediately before the :. If ! is used, BREAKING CHANGE: MAY be omitted from the footer section, and the commit description SHALL be used to describe the breaking change.
14. Types other than feat and fix MAY be used in your commit messages, e.g., docs: update ref docs.

ADDITIONAL GUIDELINES:
- Description: Use lowercase, imperative mood, no ending period, max 50 chars
- Body: ONLY include if changes require explanation beyond description. Keep concise.
- Body: ONLY inlcude a body, if its a non-trivial change that requires additional context.
- Body: Wrap at 72 characters per line, explain WHAT and WHY (not HOW)
- Type casing: Any casing may be used, but be consistent (prefer lowercase)
- SemVer relationship: fix = PATCH, feat = MINOR, BREAKING CHANGE = MAJOR
- Revert commits: Use "revert" type with footer referencing commit SHAs
- BREAKING CHANGE: Use SPARINGLY. ONLY for big, actual breaking changes.
- BREAKING CHANGE: Adding new features is NOT breaking. Only for removed/changed functionality.

Current branch: %s

Recent commits:
%s


Staged changes:
```
%s
```

Generate ONLY the commit message following the specification above:]]

-- State
local state = {
  copilot_token = nil,
  oauth_token = nil,
  ns_id = nil,
  log = nil,
  in_flight_buffers = {},
}

-- Get preferences file path
local function get_preferences_file()
  if vim and vim.fn then
    return vim.fn.stdpath 'data' .. '/ai-commit-preferences.json'
  end
  return nil
end

-- Load saved preferences
local function load_preferences()
  local prefs_file = get_preferences_file()
  if not prefs_file then
    return
  end

  local file = io.open(prefs_file, 'r')
  if file then
    local content = file:read '*a'
    file:close()
    local ok, prefs = pcall(vim.json.decode, content)
    if ok and type(prefs) == 'table' then
      CONFIG.model = prefs.model
      if type(prefs.model_name) == 'string' and prefs.model_name ~= '' then
        CONFIG.model_name = prefs.model_name
      else
        CONFIG.model_name = nil
      end
    end
  end
end

-- Save preferences
local function save_preferences()
  local prefs_file = get_preferences_file()
  if not prefs_file then
    return false
  end

  local prefs = {
    model = CONFIG.model,
    model_name = CONFIG.model_name,
  }
  local file = io.open(prefs_file, 'w')
  if file then
    file:write(vim.json.encode(prefs))
    file:close()
    return true
  end
  return false
end

-- Logging
---@return table
local function setup_logger()
  if state.log then
    return state.log
  end

  local ok, plenary_log = pcall(require, 'plenary.log')
  if not ok then
    -- Fallback noop logger if plenary.log fails
    local noop = function() end
    state.log = { debug = noop, info = noop, warn = noop, error = noop }
    return state.log
  end

  state.log = plenary_log.new {
    plugin = 'ai-commit',
    level = CONFIG.log_level or 'info',
    use_console = false,
  }

  return state.log
end

-- Authentication

---@param body string|nil
---@param max_len integer|nil
---@return string
local function format_body_for_log(body, max_len)
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

---@return string
local function get_selected_model_name()
  if type(CONFIG.model_name) == 'string' and CONFIG.model_name ~= '' then
    return CONFIG.model_name
  end
  if type(CONFIG.model) == 'string' and CONFIG.model ~= '' then
    return CONFIG.model
  end
  return 'Copilot default'
end

-- Try to get headers from Avante's copilot provider (so we don't maintain them)
local function get_copilot_headers()
  local ok, avante_copilot = pcall(require, 'avante.providers.copilot')
  if ok and avante_copilot and avante_copilot.build_headers then
    -- Use Avante's headers by calling its build_headers method
    local success, headers = pcall(avante_copilot.build_headers, avante_copilot)
    if success and headers then
      -- Remove Authorization since we'll add our own
      headers['Authorization'] = nil
      return headers
    end
  end

  -- Fallback headers if Avante is not available
  return {
    ['User-Agent'] = 'GitHubCopilotChat/0.26.7',
    ['Editor-Version'] = 'vscode/1.105.1',
    ['Editor-Plugin-Version'] = 'copilot-chat/0.26.7',
    ['Copilot-Integration-Id'] = 'vscode-chat',
  }
end

--- Find GitHub Copilot config directory
---@return string
local function get_copilot_config_dir()
  local xdg_config = vim.fn.expand '$XDG_CONFIG_HOME'

  if xdg_config and vim.fn.isdirectory(xdg_config) > 0 then
    return xdg_config
  elseif vim.fn.has 'unix' == 1 then
    return vim.fn.expand '~/.config'
  else
    return vim.fn.expand '~/AppData/Local'
  end
end

--- Get OAuth token from Copilot config files
---@return string|nil
local function get_oauth_token()
  local log = setup_logger()

  if state.oauth_token then
    log.debug 'Using cached OAuth token'
    return state.oauth_token
  end

  log.debug 'Searching for Copilot OAuth token'
  local Path = require 'plenary.path'
  local config_dir = get_copilot_config_dir()
  log.debug('Config directory: ' .. config_dir)

  for _, filename in ipairs { 'hosts.json', 'apps.json' } do
    local token_path = Path:new(config_dir):joinpath('github-copilot', filename)
    log.debug('Checking: ' .. token_path:absolute())

    if token_path:exists() then
      local ok, data = pcall(vim.json.decode, token_path:read())
      if ok then
        for key, value in pairs(data) do
          if key:match 'github.com' and value.oauth_token then
            state.oauth_token = value.oauth_token
            log.info('Found OAuth token in ' .. filename)
            return state.oauth_token
          end
        end
      else
        log.warn('Failed to parse ' .. filename)
      end
    end
  end

  log.error 'Copilot OAuth token not found'
  -- vim.notify('Copilot OAuth token not found. Please authenticate with Copilot.', vim.log.levels.ERROR)
  return nil
end

--- Exchange OAuth token for Copilot API token (async)
---@param callback function(string|nil)
---@param request_context table|nil
local function get_api_token_async(callback, request_context)
  local log = setup_logger()

  local function is_cancelled()
    return request_context and request_context.is_cancelled and request_context.is_cancelled()
  end

  local function register_http_job(job)
    if request_context and request_context.register_http_job then
      request_context.register_http_job(job)
    end
  end

  -- Return cached token if still valid
  if state.copilot_token and state.copilot_token.expires_at > os.time() then
    log.debug 'Using cached API token'
    if is_cancelled() then
      return
    end
    callback(state.copilot_token.token)
    return
  end

  local oauth_token = get_oauth_token()
  if not oauth_token then
    callback(nil)
    return
  end

  log.info 'Exchanging OAuth token for API token'
  local curl = require 'plenary.curl'

  local job = curl.get(COPILOT_AUTH_URL, {
    headers = {
      ['Authorization'] = 'token ' .. oauth_token,
      ['Accept'] = 'application/json',
    },
    timeout = 5000,
    callback = vim.schedule_wrap(function(response)
      if is_cancelled() then
        log.debug 'Ignoring Copilot auth response for cancelled request'
        return
      end

      if response.status ~= 200 then
        local response_body = format_body_for_log(response.body)
        log.error(string.format('Failed to authenticate with Copilot: %d body=%s', response.status, response_body))
        vim.notify('Copilot authentication failed (' .. response.status .. '). See ai-commit logs for response body.', vim.log.levels.ERROR)
        callback(nil)
        return
      end

      local ok, decoded = pcall(vim.json.decode, response.body)
      if not ok or type(decoded) ~= 'table' then
        log.error('Failed to parse Copilot auth response body=' .. format_body_for_log(response.body))
        vim.notify('Failed to parse Copilot authentication response. See ai-commit logs.', vim.log.levels.ERROR)
        callback(nil)
        return
      end

      if not decoded.token or not decoded.expires_at then
        log.error('Copilot auth response missing required fields body=' .. format_body_for_log(response.body))
        vim.notify('Copilot authentication response was incomplete. See ai-commit logs.', vim.log.levels.ERROR)
        callback(nil)
        return
      end

      state.copilot_token = decoded
      local expires_in = state.copilot_token.expires_at - os.time()
      log.info(string.format('API token acquired (expires in %ds)', expires_in))
      callback(state.copilot_token.token)
    end),
    on_error = vim.schedule_wrap(function(err)
      if is_cancelled() then
        log.debug 'Copilot auth request cancelled'
        return
      end

      local stderr = err and err.stderr or '<no stderr>'
      log.error('Copilot auth request failed: ' .. tostring(stderr))
      vim.notify('Copilot authentication request failed. See ai-commit logs.', vim.log.levels.ERROR)
      callback(nil)
    end),
  })

  register_http_job(job)
end

-- Git Operations

--- Get git comment character
---@return string
local function get_comment_char()
  local result = vim.fn.system('git config core.commentChar'):gsub('%s+$', '')
  if result == '' or result == 'auto' then
    return '#'
  end
  return result
end

--- Get current branch name (async with plenary)
---@param callback function(string)
local function get_current_branch_async(callback)
  local Job = require 'plenary.job'
  Job:new({
    command = 'git',
    args = { 'branch', '--show-current' },
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        callback 'unknown'
        return
      end
      local result = table.concat(job:result(), '\n'):gsub('%s+$', '')
      callback(result)
    end),
  }):start()
end

--- Get recent commit titles (async with plenary)
---@param count integer
---@param callback function(string)
local function get_recent_commits_async(count, callback)
  count = count or 5
  local Job = require 'plenary.job'
  Job:new({
    command = 'git',
    args = { 'log', '-n', tostring(count), '--format=%h %s' },
    on_exit = vim.schedule_wrap(function(job, code)
      if code ~= 0 then
        callback 'No recent commits available'
        return
      end
      local result = table.concat(job:result(), '\n')
      callback(result)
    end),
  }):start()
end

--- Get staged changes diff (async with plenary)
---@param callback function(string|nil, table|nil)
local function get_staged_diff_async(callback)
  local log = setup_logger()
  log.debug 'Getting staged changes diff'

  local Job = require 'plenary.job'
  Job
    :new({
      command = 'git',
      args = { 'diff', '--cached', '--no-color', '--no-ext-diff' },
      on_exit = vim.schedule_wrap(function(job, code)
        if code ~= 0 then
          log.error 'Failed to get staged changes'
          callback(nil, nil)
          return
        end

        local result = table.concat(job:result(), '\n')
        if result == '' or result:match '^%s*$' then
          log.warn 'No staged changes found'
          callback(nil, nil)
          return
        end

        local diff_meta = {
          original_chars = #result,
          sent_chars = #result,
          truncated = false,
        }

        if #result > CONFIG.max_diff_chars then
          local head_len = math.floor(CONFIG.max_diff_chars * 0.7)
          local tail_len = CONFIG.max_diff_chars - head_len
          local tail_start = #result - tail_len + 1
          if tail_start < 1 then
            tail_start = 1
          end

          local marker = string.format('\n\n[... diff truncated by ai_commit: original=%d chars, kept=%d chars ...]\n\n', #result, CONFIG.max_diff_chars)
          result = result:sub(1, head_len) .. marker .. result:sub(tail_start)
          diff_meta.truncated = true
          diff_meta.sent_chars = #result
          log.warn(string.format('Staged diff exceeded max size, truncated to %d chars', CONFIG.max_diff_chars))
        end

        local diff_size = #result
        log.info(string.format('Got staged diff (%d bytes)', diff_size))
        callback(result, diff_meta)
      end),
    })
    :start()
end

--- Check if buffer has existing commit message content
---@param bufnr integer
---@return boolean
local function buffer_has_content(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local comment_char = get_comment_char()

  for _, line in ipairs(lines) do
    if not line:match('^' .. vim.pesc(comment_char)) and line:match '%S' then
      return true
    end
  end

  return false
end

-- AI Generation

--- Clean up AI-generated message
---@param message string
---@return string
local function clean_message(message)
  local result = message:gsub('^%s*```.-\n', ''):gsub('\n```%s*$', ''):gsub('^%s+', ''):gsub('%s+$', '')
  return result
end

--- Generate commit message using Copilot (async)
---@param branch string
---@param recent_commits string
---@param diff string
---@param callback function(string|nil, table|nil)
---@param status_callback function(string)|nil
---@param request_context table|nil
local function generate_commit_message_async(branch, recent_commits, diff, callback, status_callback, request_context)
  local log = setup_logger()
  log.info 'Starting commit message generation'

  local function is_cancelled()
    return request_context and request_context.is_cancelled and request_context.is_cancelled()
  end

  local function register_http_job(job)
    if request_context and request_context.register_http_job then
      request_context.register_http_job(job)
    end
  end

  local function report_status(message)
    if status_callback then
      status_callback(message)
    end
  end

  local requested_model = get_selected_model_name()

  report_status 'Authenticating with Copilot'

  get_api_token_async(function(token)
    if is_cancelled() then
      log.debug 'Generation cancelled before API token usage'
      return
    end

    if not token then
      log.error 'Failed to get API token'
      vim.notify('Could not get Copilot API token. See ai-commit logs.', vim.log.levels.ERROR)
      callback(nil, nil)
      return
    end

    local curl = require 'plenary.curl'
    local endpoint = (state.copilot_token.endpoints and state.copilot_token.endpoints.api) or COPILOT_API_ENDPOINT
    log.debug('Using endpoint: ' .. endpoint)

    local start_time = vim.uv.hrtime()

    local headers = get_copilot_headers()
    headers['Authorization'] = 'Bearer ' .. token
    headers['Content-Type'] = 'application/json'

    -- Format the full prompt with context
    report_status 'Preparing prompt'
    local full_prompt = string.format(COMMIT_PROMPT_TEMPLATE, branch, recent_commits, diff)
    log.debug(string.format('Prompt built (branch=%s, commits=%d chars, diff=%d chars)', branch, #recent_commits, #diff))
    log.debug('Full prompt being sent to AI:\n' .. string.rep('=', 80) .. '\n' .. full_prompt .. '\n' .. string.rep('=', 80))

    local request_body = {
      messages = { { role = 'user', content = full_prompt } },
      stream = false,
      temperature = CONFIG.temperature,
      max_tokens = CONFIG.max_tokens,
    }

    -- Only include model if explicitly set
    if CONFIG.model then
      request_body.model = CONFIG.model
    end

    report_status('Waiting for response from ' .. requested_model)

    local job = curl.post(endpoint .. '/chat/completions', {
      headers = headers,
      body = vim.json.encode(request_body),
      timeout = CONFIG.chat_timeout,
      callback = vim.schedule_wrap(function(response)
        if is_cancelled() then
          log.debug 'Ignoring Copilot chat response for cancelled request'
          return
        end

        local elapsed_ms = (vim.uv.hrtime() - start_time) / 1e6

        if response.status ~= 200 then
          local response_body = format_body_for_log(response.body)
          log.error(string.format('Copilot API error: %d (took %.0fms) body=%s', response.status, elapsed_ms, response_body))
          vim.notify('Copilot API request failed (' .. response.status .. '). See ai-commit logs for response body.', vim.log.levels.ERROR)
          callback(nil, nil)
          return
        end

        local ok, data = pcall(vim.json.decode, response.body)
        if not ok or not data.choices or not data.choices[1] or not data.choices[1].message then
          log.error('Failed to parse Copilot response body=' .. format_body_for_log(response.body))
          vim.notify('Failed to parse Copilot response. See ai-commit logs for response body.', vim.log.levels.ERROR)
          callback(nil, nil)
          return
        end

        local message = clean_message(data.choices[1].message.content)
        local used_model = data.model or request_body.model or 'auto'
        log.info(string.format('Generated commit message (took %.0fms, model=%s): %s', elapsed_ms, used_model, message:sub(1, 50) .. '...'))
        callback(message, { requested_model = requested_model, used_model = used_model })
      end),
      on_error = vim.schedule_wrap(function(err)
        if is_cancelled() then
          log.debug 'Copilot chat request cancelled'
          return
        end

        local stderr = err and err.stderr or '<no stderr>'
        log.error('Copilot chat request failed: ' .. tostring(stderr))
        vim.notify('Copilot API request failed. See ai-commit logs.', vim.log.levels.ERROR)
        callback(nil, nil)
      end),
    })

    register_http_job(job)
  end, request_context)
end

--- Get available Copilot models
---@return table models
local function get_copilot_models()
  local log = setup_logger()

  -- Try to use Avante's model list if available
  local ok, avante_copilot = pcall(require, 'avante.providers.copilot')
  if ok and avante_copilot and avante_copilot.list_models then
    log.info 'Getting models from Avante copilot provider'
    local success, models = pcall(avante_copilot.list_models, avante_copilot)
    if success and models and #models > 0 then
      log.info(string.format('Got %d models from Avante', #models))
      -- Avante returns models with structure: { id, name, display_name, policy, version, ... }
      return models
    end
  end

  log.info 'Using fallback model list'
  local fallback_models = {
    { id = 'gpt-4o-2024-11-20', name = 'GPT-4o' },
    { id = 'gpt-4o-mini', name = 'GPT-4o Mini' },
    { id = 'gpt-4o', name = 'GPT-4o' },
    { id = 'gpt-5-mini', name = 'GPT-5 mini' },
  }

  return fallback_models
end

--- Select and save a Copilot model
local function select_model()
  local models = get_copilot_models()

  if not models or #models == 0 then
    vim.notify('No models available', vim.log.levels.ERROR)
    return
  end

  -- Filter out disabled models and duplicates
  local enabled_models = {}
  local seen_ids = {}
  for _, model in ipairs(models) do
    -- Skip if already seen this model ID
    if model.id and seen_ids[model.id] then
      goto continue
    end

    local is_disabled = false
    if model.policy and type(model.policy) == 'table' then
      local state = model.policy.state
      if state == 'disabled' or state == 'unconfigured' then
        is_disabled = true
      end
    elseif model.policy == false then
      is_disabled = true
    end

    if not is_disabled then
      table.insert(enabled_models, model)
      if model.id then
        seen_ids[model.id] = true
      end
    end

    ::continue::
  end

  -- Sort models alphabetically by display name
  table.sort(enabled_models, function(a, b)
    local name_a = a.display_name or a.name or a.id or ''
    local name_b = b.display_name or b.name or b.id or ''
    return name_a < name_b
  end)

  -- Add "Auto (use default)" option at the top
  table.insert(enabled_models, 1, { id = nil, name = 'Auto (use default)' })

  -- Get current model from CONFIG
  local current_model = CONFIG.model

  vim.ui.select(enabled_models, {
    prompt = 'Select Copilot Model:',
    format_item = function(model)
      local is_current = (model.id == current_model) or (not model.id and not current_model)
      local marker = is_current and '✓ ' or '  '

      -- Use display_name or name for the friendly name
      local display_name = model.display_name or model.name or model.id or 'Unknown'

      -- Build display string
      local display = display_name

      -- Add ID in parentheses if different from display name
      if model.id and model.id ~= display_name then
        display = display .. ' (' .. model.id .. ')'
      end

      return marker .. display
    end,
  }, function(choice)
    if not choice then
      return
    end

    -- Update runtime config
    CONFIG.model = choice.id
    CONFIG.model_name = choice.display_name or choice.name or choice.id
    if not CONFIG.model then
      CONFIG.model_name = nil
    end

    local log = setup_logger()
    log.info('Model changed to: ' .. get_selected_model_name())

    -- Save to preferences file (NOT the config file!)
    save_preferences()
    -- if save_preferences() then
    --    vim.notify('Model saved: ' .. (choice.id or 'Auto'), vim.log.levels.INFO)
    -- else
    --    vim.notify('Model set: ' .. (choice.id or 'Auto') .. ' (could not save)', vim.log.levels.WARN)
    -- end
  end)
end

-- UI - Spinner

--- Create and start spinner animation
---@param bufnr integer
---@return table spinner
local function start_spinner(bufnr)
  local log = setup_logger()
  log.debug('Starting spinner for buffer ' .. bufnr)

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

  local spinner = {
    timer = nil,
    extmark_id = nil,
    status_text = 'Preparing commit message',
    status_chunks = { { 'Preparing commit message', 'Comment' } },
    stop_timer = stop_timer_safe,
  }

  local frame_idx = 1

  local function update_spinner()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      log.debug 'Buffer no longer valid, stopping spinner timer'
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

    local virt_text = { { SPINNER_FRAMES[frame_idx] .. ' ', 'Comment' } }
    if spinner.status_chunks and #spinner.status_chunks > 0 then
      vim.list_extend(virt_text, spinner.status_chunks)
    else
      table.insert(virt_text, { spinner.status_text, 'Comment' })
    end

    spinner.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, row, col, {
      id = spinner.extmark_id,
      right_gravity = false,
      virt_text = virt_text,
      virt_text_pos = 'eol',
    })

    frame_idx = (frame_idx % #SPINNER_FRAMES) + 1
  end

  update_spinner()
  local timer = vim.uv.new_timer()
  if timer then
    timer:start(CONFIG.spinner_interval, CONFIG.spinner_interval, vim.schedule_wrap(update_spinner))
  end
  spinner.timer = timer
  spinner.update = update_spinner

  return spinner
end

---@param spinner table|nil
---@param status_text string
---@param status_chunks table|nil
local function set_spinner_status(spinner, status_text, status_chunks)
  if not spinner then
    return
  end

  spinner.status_text = status_text
  spinner.status_chunks = status_chunks
  if spinner.update then
    spinner.update()
  end
end

--- Stop spinner and clear virtual text
---@param bufnr integer
---@param spinner table
---@return integer insert_row
local function stop_spinner(bufnr, spinner)
  local log = setup_logger()
  log.debug('Stopping spinner for buffer ' .. bufnr)

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

-- Main Logic

--- Insert AI-generated commit message into buffer (async)
local function insert_ai_commit_message()
  local log = setup_logger()

  if vim.bo.filetype ~= 'gitcommit' then
    log.debug 'Not a gitcommit buffer, skipping'
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  log.info('Starting AI commit message generation for buffer ' .. bufnr)

  if buffer_has_content(bufnr) then
    log.debug 'Buffer already has content, skipping'
    return
  end

  if state.in_flight_buffers[bufnr] then
    log.debug('Generation already in progress for buffer ' .. bufnr)
    return
  end

  state.in_flight_buffers[bufnr] = true

  local spinner = start_spinner(bufnr)
  local done = false
  local aborted = false
  local http_jobs = {}
  local context_total = 3
  local context_done = 0
  local last_status_line = nil

  local function register_http_job(job)
    if not job then
      return
    end
    table.insert(http_jobs, job)
  end

  local function abort_http_jobs()
    for _, job in ipairs(http_jobs) do
      if job and job.shutdown and not job.is_shutdown then
        pcall(job.shutdown, job, 0, 15)
      end
    end
    http_jobs = {}
  end

  local request_context = {
    is_cancelled = function()
      return done or aborted
    end,
    register_http_job = register_http_job,
  }

  local context = {
    branch = nil,
    recent_commits = nil,
    diff = nil,
    diff_meta = nil,
  }

  local function spinner_suffix_text()
    if context.diff_meta and context.diff_meta.truncated then
      return ' [truncated]'
    end
    return ''
  end

  local function set_stage_status(stage_text)
    if done then
      return
    end

    local status_line = stage_text .. spinner_suffix_text()

    local status_chunks = { { status_line, 'Comment' } }
    local waiting_prefix = 'Waiting for response from '
    if vim.startswith(stage_text, waiting_prefix) then
      local model_name = stage_text:sub(#waiting_prefix + 1)
      status_chunks = {
        { waiting_prefix, 'Comment' },
        { model_name, CONFIG.model_highlight_group },
      }
      local suffix = spinner_suffix_text()
      if suffix ~= '' then
        table.insert(status_chunks, { suffix, 'Comment' })
      end
    end

    set_spinner_status(spinner, status_line, status_chunks)

    if status_line ~= last_status_line then
      last_status_line = status_line
      log.debug('Status: ' .. status_line)
    end
  end

  set_stage_status(string.format('Preparing context (%d/%d)', context_done, context_total))

  local function abort_generation(reason)
    if done then
      return
    end

    done = true
    aborted = true
    abort_http_jobs()
    stop_spinner(bufnr, spinner)
    state.in_flight_buffers[bufnr] = nil

    log.info(string.format('Aborted AI commit message generation for buffer %d (%s)', bufnr, reason or 'unknown'))
  end

  vim.api.nvim_create_autocmd({ 'BufHidden', 'BufUnload', 'BufWipeout' }, {
    buffer = bufnr,
    once = true,
    callback = function()
      abort_generation 'buffer closed'
    end,
  })

  local function finalize(message)
    if done then
      return
    end

    if message then
      set_stage_status 'Inserting message'
    else
      set_stage_status 'Generation failed'
    end

    done = true

    local insert_row = stop_spinner(bufnr, spinner)
    http_jobs = {}
    state.in_flight_buffers[bufnr] = nil

    if aborted then
      return
    end

    if not message then
      log.warn 'No message generated'
      return
    end

    local lines = vim.split(message, '\n')
    local inserted = false
    if vim.api.nvim_buf_is_valid(bufnr) then
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      if insert_row < 0 then
        insert_row = 0
      elseif insert_row > line_count then
        insert_row = line_count
      end
      vim.api.nvim_buf_set_lines(bufnr, insert_row, insert_row, false, lines)
      inserted = true
    end

    if inserted then
      log.info('Successfully inserted commit message (' .. #lines .. ' lines)')
    else
      log.info 'Generated commit message but skipped insert because buffer is no longer available'
    end
  end

  -- Gather all context in parallel
  local pending = 3
  local failed = false
  local check_complete

  local function mark_context_done()
    if done then
      return
    end

    context_done = context_done + 1
    set_stage_status(string.format('Preparing context (%d/%d)', context_done, context_total))
    if check_complete then
      check_complete()
    end
  end

  check_complete = function()
    if done then
      return
    end

    pending = pending - 1
    if pending == 0 and not failed then
      -- All context gathered, generate commit message
      generate_commit_message_async(context.branch, context.recent_commits, context.diff, function(message)
        finalize(message)
      end, function(status)
        set_stage_status(status)
      end, request_context)
    elseif failed then
      finalize(nil)
    end
  end

  -- Get branch info
  get_current_branch_async(function(branch)
    if done then
      return
    end

    context.branch = branch
    mark_context_done()
  end)

  -- Get recent commits
  get_recent_commits_async(5, function(commits)
    if done then
      return
    end

    context.recent_commits = commits
    mark_context_done()
  end)

  -- Get staged diff
  get_staged_diff_async(function(diff, diff_meta)
    if done then
      return
    end

    if not diff then
      failed = true
      finalize(nil)
      return
    end
    context.diff = diff
    context.diff_meta = diff_meta
    mark_context_done()
  end)
end

-- Plugin Setup

--- @return LazySpec
return {
  'nvim-lua/plenary.nvim',
  ft = 'gitcommit',

  config = function()
    -- Load saved model preference
    load_preferences()

    local log = setup_logger()
    log.info('Using model: ' .. get_selected_model_name())

    state.ns_id = vim.api.nvim_create_namespace 'ai_commit_spinner'

    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'gitcommit',
      group = vim.api.nvim_create_augroup('AICommitMessage', { clear = true }),
      callback = function()
        log.debug 'gitcommit FileType autocmd triggered'

        vim.keymap.set('n', '<leader>ga', insert_ai_commit_message, {
          buffer = true,
          desc = '[G]it [A]I commit message',
        })

        vim.schedule(insert_ai_commit_message)
      end,
    })

    vim.api.nvim_create_user_command('AICommit', insert_ai_commit_message, {
      desc = 'Generate AI commit message',
    })

    vim.api.nvim_create_user_command('AICommitModels', select_model, {
      desc = 'Select Copilot model for commit messages',
    })
  end,
}
