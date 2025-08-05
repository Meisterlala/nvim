-- sync.lua: Neovim config git utilities
local M = {}

-- Define internal state within M
M.nvim_config_git_status = ''
M.git_check_in_progress = false
M.commit_is_running = false

function M.refresh_nvim_config_git_status()
  if M.git_check_in_progress then
    return
  end
  M.git_check_in_progress = true

  local nvim_config_path = vim.fn.stdpath 'config'
  if vim.fn.isdirectory(nvim_config_path) == 0 then
    M.nvim_config_git_status = 'Config Dir Not Found!'
    M.git_check_in_progress = false
    vim.cmd 'redrawstatus'
    return
  end

  -- Check for the current git branch
  vim.system({ 'git', '-C', nvim_config_path, 'rev-parse', '--abbrev-ref', 'HEAD' }, {
    text = true,
  }, function(branch_result)
    if branch_result.code ~= 0 then
      -- On failure to get the branch
      M.nvim_config_git_status = 'Failed to fetch branch'
      M.git_check_in_progress = false
      return
    end

    local current_branch = (branch_result.stdout or ''):gsub('\n', '')
    if current_branch == '' then
      M.nvim_config_git_status = 'Not a Git Repo!'
      M.git_check_in_progress = false
      return
    end

    -- Check the git status for uncommitted changes
    vim.system({ 'git', '-C', nvim_config_path, 'status', '--porcelain' }, {
      text = true,
    }, function(status_result)
      -- On failure to get git status
      if status_result.code ~= 0 then
        M.nvim_config_git_status = 'Failed to fetch status'
        M.git_check_in_progress = false
        return
      end

      local has_uncommitted_changes = #status_result.stdout > 0
      local status_message = '⚡ nvim config updated'

      if current_branch ~= 'master' and current_branch ~= 'main' then
        status_message = status_message .. ' (' .. current_branch .. ')'
      end

      M.nvim_config_git_status = has_uncommitted_changes and status_message or ''
      vim.schedule(function()
        vim.cmd 'redrawstatus'
      end)
      M.git_check_in_progress = false
    end)
  end)
end

--- Get current nvim config git status string
function M.get_nvim_config_git_status()
  return M.nvim_config_git_status
end

-- Trigger Git status check when nvim config files are saved
vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  pattern = {
    vim.fn.stdpath 'config' .. '*',
    vim.fn.stdpath 'config' .. '**/*',
    vim.fn.stdpath 'config' .. '**\\*',
    '*/nvim/**/*',
    '*\\nvim\\**\\*',
  },
  callback = function()
    M.refresh_nvim_config_git_status()
  end,
})

-- Commit and push changes in the nvim config git repo
function M.commit_and_push_config_changes()
  if M.commit_is_running then
    vim.notify('Config push is already running...', vim.log.levels.WARN)
    return
  end
  M.commit_is_running = true
  vim.notify 'Pushing config to remote repo...'

  local config_dir = vim.fn.stdpath 'config'
  local git_executable = vim.fn.executable 'git'

  if not git_executable then
    vim.notify('Git is not installed or not in PATH.', vim.log.levels.ERROR)
    M.commit_is_running = false
    return
  end

  -- Check for changes (async)
  vim.system({ 'git', 'diff', '--quiet' }, { text = true, cwd = config_dir }, function(obj)
    if obj.code == 0 then
      vim.schedule(function()
        vim.notify('No changes to commit.', vim.log.levels.INFO)
        M.commit_is_running = false
      end)
      return
    end

    -- Stage changes
    vim.system({ 'git', 'add', '.' }, { text = true, cwd = config_dir }, function(add_obj)
      if add_obj.code ~= 0 then
        vim.schedule(function()
          vim.notify('Failed to add changes:\n' .. add_obj.stderr, vim.log.levels.ERROR)
          M.commit_is_running = false
        end)
        return
      end

      -- Commit
      local timestamp = tostring(os.date '%Y-%m-%d-%H:%M:%S')
      vim.system({ 'git', 'commit', '-m', timestamp }, { text = true, cwd = config_dir }, function(commit_obj)
        if commit_obj.code ~= 0 then
          vim.schedule(function()
            vim.notify('Failed to commit:\n' .. commit_obj.stderr, vim.log.levels.ERROR)
            M.commit_is_running = false
          end)
          return
        end

        -- Push
        vim.system({ 'git', 'push' }, { text = true, cwd = config_dir }, function(push_obj)
          vim.schedule(function()
            if push_obj.code ~= 0 then
              vim.notify('Failed to push:\n' .. push_obj.stderr, vim.log.levels.ERROR)
            else
              vim.notify('Config changes committed and pushed.', vim.log.levels.INFO)
            end
            M.commit_is_running = false
            if M.refresh_nvim_config_git_status then
              M.refresh_nvim_config_git_status()
            end
          end)
        end)
      end)
    end)
  end)
end

vim.api.nvim_create_user_command('SyncConfigPush', M.commit_and_push_config_changes, {})
vim.api.nvim_create_user_command('SyncUpdateStatus', M.refresh_nvim_config_git_status, {})

return M
