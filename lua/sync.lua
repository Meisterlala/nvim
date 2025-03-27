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
  local diff_result = vim.fn.systemlist 'git diff --quiet'
  local diff_status = vim.v.shell_error

  if diff_status == 0 then
    vim.notify('No changes to commit.', vim.log.levels.INFO)
    vim.fn.chdir(current_dir)
    return
  end

  -- Add all changes
  local add_result = vim.fn.systemlist 'git add .'
  local add_status = vim.v.shell_error

  if add_status ~= 0 then
    vim.notify('Failed to add changes:\n' .. table.concat(add_result, '\n'), vim.log.levels.ERROR)
    vim.fn.chdir(current_dir)
    return
  end

  -- Commit changes with simple message
  local timestamp = os.date '%Y-%m-%d-%H:%M:%S'
  local message = timestamp
  local commit_command = 'git commit -m "' .. message .. '"'
  local commit_result = vim.fn.systemlist(commit_command)
  local commit_status = vim.v.shell_error

  if commit_status ~= 0 then
    vim.notify('Failed to commit changes:\n' .. table.concat(commit_result, '\n'), vim.log.levels.ERROR)
    vim.fn.chdir(current_dir)
    return
  end

  -- Push changes
  local push_result = vim.fn.systemlist 'git push'
  local push_status = vim.v.shell_error

  if push_status ~= 0 then
    vim.notify('Failed to push changes:\n' .. table.concat(push_result, '\n'), vim.log.levels.ERROR)
    vim.fn.chdir(current_dir)
    return
  end

  vim.notify('Config changes committed and pushed.', vim.log.levels.INFO)
  vim.fn.chdir(current_dir)
end

vim.api.nvim_create_user_command('ConfigPush', commit_and_push_config_changes, {})
