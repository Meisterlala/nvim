-- sync.lua: Neovim config git utilities

local M = {}

-- Internal state for nvim config git status
local nvim_config_git_status = ''
local git_check_in_progress = false

-- Refresh nvim config git status
function M.refresh_nvim_config_git_status()
  if git_check_in_progress then
    return
  end
  git_check_in_progress = true

  local nvim_config_path = vim.fn.stdpath 'config'
  if vim.fn.isdirectory(nvim_config_path) == 0 then
    nvim_config_git_status = 'Config Dir Not Found!'
    git_check_in_progress = false
    return
  end

  vim.fn.jobstart({
    'git',
    '-C',
    nvim_config_path,
    'rev-parse',
    '--abbrev-ref',
    'HEAD',
  }, {
    stdout_buffered = true,
    on_stdout = function(_, branch_output)
      local current_branch = (branch_output[1] or ''):gsub('\n', '')
      if current_branch == '' then
        nvim_config_git_status = 'Not a Git Repo!'
        git_check_in_progress = false
        vim.cmd 'redrawstatus'
        return
      end
      vim.fn.jobstart({
        'git',
        '-C',
        nvim_config_path,
        'status',
        '--porcelain',
      }, {
        stdout_buffered = true,
        on_stdout = function(_, status_output)
          local has_uncommitted_changes = #status_output > 1 or (status_output[1] and status_output[1] ~= '')
          local status_message = '⚡ nvim config updated'
          if current_branch ~= 'master' and current_branch ~= 'main' then
            status_message = status_message .. ' (' .. current_branch .. ')'
          end
          nvim_config_git_status = has_uncommitted_changes and status_message or ''
          git_check_in_progress = false
          vim.cmd 'redrawstatus'
        end,
        on_exit = function()
          git_check_in_progress = false
        end,
      })
    end,
    on_exit = function()
      git_check_in_progress = false
    end,
  })
end

--- Get current nvim config git status string
function M.get_nvim_config_git_status()
  return nvim_config_git_status
end

---
---

M.commit_is_running = false
-- Commit and push changes in the nvim config git repo
function M.commit_and_push_config_changes()
  if M.commit_is_running then
    vim.notify('Config push is already running...', vim.log.levels.WARN)
    return
  end
  M.commit_is_running = true

  local config_dir = vim.fn.stdpath 'config'
  local git_executable = vim.fn.executable 'git'

  if not git_executable then
    vim.notify('Git is not installed or not in PATH.', vim.log.levels.ERROR)
    M.commit_is_running = false
    return
  end

  local current_dir = vim.fn.getcwd()
  vim.fn.chdir(config_dir)

  -- Check for changes (async)
  vim.system({ 'git', 'diff', '--quiet' }, { text = true }, function(obj)
    if obj.code == 0 then
      vim.schedule(function()
        vim.notify('No changes to commit.', vim.log.levels.INFO)
        vim.fn.chdir(current_dir)
        M.commit_is_running = false
      end)
      return
    end

    -- Stage changes
    vim.system({ 'git', 'add', '.' }, { text = true }, function(add_obj)
      if add_obj.code ~= 0 then
        vim.schedule(function()
          vim.notify('Failed to add changes:\n' .. add_obj.stderr, vim.log.levels.ERROR)
          vim.fn.chdir(current_dir)
          M.commit_is_running = false
        end)
        return
      end

      -- Commit
      local timestamp = tostring(os.date '%Y-%m-%d-%H:%M:%S')
      vim.system({ 'git', 'commit', '-m', timestamp }, { text = true }, function(commit_obj)
        if commit_obj.code ~= 0 then
          vim.schedule(function()
            vim.notify('Failed to commit:\n' .. commit_obj.stderr, vim.log.levels.ERROR)
            vim.fn.chdir(current_dir)
            M.commit_is_running = false
          end)
          return
        end

        -- Push
        vim.system({ 'git', 'push' }, { text = true }, function(push_obj)
          vim.schedule(function()
            if push_obj.code ~= 0 then
              vim.notify('Failed to push:\n' .. push_obj.stderr, vim.log.levels.ERROR)
            else
              vim.notify('Config changes committed and pushed.', vim.log.levels.INFO)
              if M.refresh_nvim_config_git_status then
                M.refresh_nvim_config_git_status()
              end
            end
            vim.fn.chdir(current_dir)
            M.commit_is_running = false
          end)
        end)
      end)
    end)
  end)
end

vim.api.nvim_create_user_command('ConfigPush', M.commit_and_push_config_changes, {})

return M
