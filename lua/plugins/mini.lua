local sync = require 'sync'

-- Returns Lazy plugin updates status if checker.enabled is true
local function lazy_updates_status()
  local ok, lazy_config = pcall(require, 'lazy.core.config')
  if not ok or not lazy_config or not lazy_config.options or not lazy_config.options.checker or not lazy_config.options.checker.enabled then
    return ''
  end
  local ok_status, lazy_status = pcall(require, 'lazy.status')
  if not ok_status or not lazy_status.updates then
    return ''
  end
  return lazy_status.updates() or ''
end

-- Returns nvim config git status if sync module and function exist
local function sync_git_status()
  local ok, sync_mod = pcall(require, 'sync')
  if not ok or not sync_mod or type(sync_mod.get_nvim_config_git_status) ~= 'function' then
    return ''
  end
  return sync_mod.get_nvim_config_git_status() or ''
end

return { -- Collection of various small independent plugins/modules
  'echasnovski/mini.nvim',
  config = function()
    -- Initialize and update nvim git status using sync module
    sync.refresh_nvim_config_git_status()

    -- Trigger Git status check when nvim config files are saved
    vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
      pattern = vim.fn.stdpath 'config' .. '\\*',
      callback = sync.refresh_nvim_config_git_status,
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
          local git_status = sync_git_status()

          return MiniStatusline.combine_groups {
            { hl = mode_hl, strings = { mode } },
            { hl = 'MiniStatuslineDevinfo', strings = { git, diff, diagnostics, lsp } },
            '%<', -- Mark general truncate point
            { hl = 'MiniStatuslineFilename', strings = { filename } },
            '%=', -- End left alignment
            { hl = 'gitstatus', strings = { git_status } },
            { hl = 'MiniStatuslineFileinfo', strings = { fileinfo, lazy_updates_status() } },
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
