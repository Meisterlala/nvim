local nvim_config_git_status = ''
local git_check_in_progress = false

local function refresh_nvim_config_git_status()
  -- Prevent multiple simultaneous Git checks
  if git_check_in_progress then
    return
  end
  git_check_in_progress = true

  local nvim_config_path = vim.fn.stdpath 'config'

  -- Verify nvim config directory exists
  if vim.fn.isdirectory(nvim_config_path) == 0 then
    nvim_config_git_status = 'Config Dir Not Found!'
    git_check_in_progress = false
    return
  end

  -- Get current Git branch
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

      -- Check for uncommitted changes
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

          -- Build status message
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

return { -- Collection of various small independent plugins/modules
  'echasnovski/mini.nvim',
  config = function()
    -- Update nvim git status and then call it initally
    local function get_nvim_config_git_status()
      return nvim_config_git_status
    end
    refresh_nvim_config_git_status()

    -- Trigger Git status check when nvim config files are saved
    vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
      pattern = vim.fn.stdpath 'config' .. '/*',
      callback = refresh_nvim_config_git_status,
    })

    -- Better Around/Inside textobjects
    --
    -- Examples:
    --  - va)  - [V]isually select [A]round [)]paren
    --  - yinq - [Y]ank [I]nside [N]ext [Q]uote
    --  - ci'  - [C]hange [I]nside [']quote
    require('mini.ai').setup { n_lines = 500 }

    -- Add/delete/replace surroundings (brackets, quotes, etc.)
    --
    -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
    -- - sd'   - [S]urround [D]elete [']quotes
    -- - sr)'  - [S]urround [R]eplace [)] [']
    require('mini.surround').setup()

    -- Simple and easy statusline.
    --  You could remove this setup call if you don't like it,
    --  and try some other statusline plugin
    local statusline = require 'mini.statusline'
    -- set use_icons to true if you have a Nerd Font
    statusline.setup {
      content = {
        active = function()
          local mode, mode_hl = MiniStatusline.section_mode { trunc_width = 120 }
          local git = MiniStatusline.section_git { trunc_width = 40 }
          local diff = MiniStatusline.section_diff { trunc_width = 75 }
          local diagnostics = MiniStatusline.section_diagnostics { trunc_width = 75 }
          local lsp = MiniStatusline.section_lsp { trunc_width = 75 }
          local filename = MiniStatusline.section_filename { trunc_width = 140 }
          local fileinfo = MiniStatusline.section_fileinfo { trunc_width = 120 }
          local location = MiniStatusline.section_location { trunc_width = 75 }
          local search = MiniStatusline.section_searchcount { trunc_width = 75 }
          local git_status = get_nvim_config_git_status()

          return MiniStatusline.combine_groups {
            { hl = mode_hl, strings = { mode } },
            { hl = 'MiniStatuslineDevinfo', strings = { git, diff, diagnostics, lsp } },
            '%<', -- Mark general truncate point
            { hl = 'MiniStatuslineFilename', strings = { filename } },
            '%=', -- End left alignment
            { hl = 'gitstatus', strings = { git_status } },
            { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
            { hl = mode_hl, strings = { search, location } },
          }
        end,
      },
      use_icons = vim.g.have_nerd_font,
    }

    -- You can configure sections in the statusline by overriding their
    -- default behavior. For example, here we set the section for
    -- cursor location to LINE:COLUMN
    ---@diagnostic disable-next-line: duplicate-set-field
    statusline.section_location = function()
      return '%2l:%-2v'
    end

    -- ... and there is more!
    --  Check out: https://github.com/echasnovski/mini.nvim
  end,
}
