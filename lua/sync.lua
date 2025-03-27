local function commit_and_push_config_changes()
  local config_dir = vim.fn.stdpath 'config'
  local git_executable = vim.fn.executable 'git'

  if not git_executable then
    vim.notify('Git is not installed or not in PATH.', vim.log.levels.ERROR)
    return
  end

  local current_dir = vim.fn.getcwd()
  vim.fn.chdir(config_dir)

  -- Check for changes
  local diff_handle = io.popen 'git diff --quiet'
  local diff_status = diff_handle:close()

  if diff_status == 0 then
    vim.notify('No changes to commit.', vim.log.levels.INFO)
    vim.fn.chdir(current_dir)
    return
  end

  -- Add all changes
  local add_handle = io.popen 'git add .'
  if not add_handle then
    vim.notify('Failed to add changes.', vim.log.levels.ERROR)
    vim.fn.chdir(current_dir)
    return
  end
  add_handle:close()

  -- Commit changes with simple message
  local commit_command = "git commit -m 'Config update'"
  local commit_handle = io.popen(commit_command)
  local commit_status = commit_handle:close() --check exit code.
  if commit_status ~= 0 then
    vim.notify('Failed to commit changes.', vim.log.levels.ERROR)
    vim.fn.chdir(current_dir)
    return
  end

  -- Push changes
  local push_handle = io.popen 'git push'
  local push_status = push_handle:close()
  if push_status ~= 0 then
    vim.notify('Failed to push changes.', vim.log.levels.ERROR)
    vim.fn.chdir(current_dir)
    return
  end

  vim.notify('Config changes committed and pushed.', vim.log.levels.INFO)
  vim.fn.chdir(current_dir)
end

vim.api.nvim_create_user_command('ConfigPush', commit_and_push_config_changes, {})
