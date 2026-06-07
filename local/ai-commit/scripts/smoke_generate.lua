local test_opts = type(vim.g.ai_commit_test) == 'table' and vim.g.ai_commit_test or {}

local function opt(name, default)
  local value = test_opts[name]
  if value == nil then
    return default
  end
  return value
end

local repo = opt('repo', vim.fn.getcwd())
local output = opt('output', '/tmp/ai-commit-message.txt')
local timeout_ms = tonumber(opt('timeout_ms', 180000)) or 180000
local staged_file = opt('staged_file', nil)
local staged_content = opt('staged_content', 'ai-commit smoke test\n')
local real_provider = opt('real_provider', false) == true

local function finish(code, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(output, ':h'), 'p')
  vim.fn.writefile(lines, output)
  if vim.api.nvim_buf_is_valid(0) then
    vim.bo.modified = false
  end
  if code == 0 then
    vim.cmd 'qa!'
  else
    vim.cmd('cquit ' .. tostring(code))
  end
end

local function system_ok(cmd)
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

vim.cmd('cd ' .. vim.fn.fnameescape(repo))

if staged_file and staged_file ~= '' then
  vim.fn.mkdir(vim.fn.fnamemodify(staged_file, ':h'), 'p')
  vim.fn.writefile(vim.split(staged_content, '\n', { plain = true }), staged_file)
  if not system_ok({ 'git', 'add', staged_file }) then
    finish(2, { 'failed to stage test file: ' .. staged_file })
    return
  end
end

local staged_diff = vim.fn.system { 'git', 'diff', '--cached', '--no-color', '--no-ext-diff' }
if vim.v.shell_error ~= 0 or staged_diff:match '^%s*$' then
  finish(2, { 'no staged diff available for ai-commit smoke test' })
  return
end

vim.opt.runtimepath:append(vim.fn.stdpath 'config' .. '/local/ai-commit')

if not real_provider then
  package.loaded['ai-provider'] = {
    setup = function() end,
    register_source = function() end,
    get_source_selection = function()
      return { provider = 'fake', model = 'fake-model', label = 'fake-model' }
    end,
    get_default_provider = function()
      return 'fake'
    end,
    get_selected_model = function()
      return 'fake-model'
    end,
    check = function(_, callback)
      vim.schedule(function()
        callback(true)
      end)
    end,
    chat = function(_, opts)
      vim.schedule(function()
        local prompt = opts.prompt or ''
        if prompt:match '^Summarize the following' then
          opts.callback('Smoke summary: recent assistant context was loaded and summarized for commit generation.', { used_model = 'fake-model' })
        else
          opts.callback('test: generate smoke commit', { used_model = 'fake-model' })
        end
      end)
    end,
  }
end

local ok, ai_commit = pcall(require, 'ai-commit')
if not ok then
  finish(2, { 'failed to require ai-commit: ' .. tostring(ai_commit) })
  return
end

ai_commit.setup {
  log_level = 'debug',
}

local commit_file = opt('commit_file', repo .. '/.git/COMMIT_EDITMSG')
vim.cmd('edit! ' .. vim.fn.fnameescape(commit_file))
vim.bo.filetype = 'gitcommit'
vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

ai_commit.insert()

local bufnr = vim.api.nvim_get_current_buf()
local comment_char = vim.fn.system('git config core.commentChar'):gsub('%s+$', '')
if comment_char == '' or comment_char == 'auto' then
  comment_char = '#'
end

local function generated_lines()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local result = {}
  for _, line in ipairs(lines) do
    if not line:match('^' .. vim.pesc(comment_char)) and line:match '%S' then
      table.insert(result, line)
    end
  end
  return result
end

local completed = vim.wait(timeout_ms, function()
  return #generated_lines() > 0
end, 250)

local lines = generated_lines()
if completed and #lines > 0 then
  table.insert(lines, '')
  table.insert(lines, '--- smoke metadata ---')
  table.insert(lines, 'repo=' .. repo)
  table.insert(lines, 'output=' .. output)
  table.insert(lines, 'diff_chars=' .. tostring(#staged_diff))
  table.insert(lines, 'real_provider=' .. tostring(real_provider))
  finish(0, lines)
  return
end

finish(1, {
  'ai-commit smoke test timed out or generated no message',
  'repo=' .. repo,
  'timeout_ms=' .. tostring(timeout_ms),
  'diff_chars=' .. tostring(#staged_diff),
  'real_provider=' .. tostring(real_provider),
})
