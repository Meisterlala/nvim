--- @type LazySpec | LazySpec[]
return {
  'nanozuki/tabby.nvim',
  event = 'VeryLazy',
  dependencies = {
    'nvim-tree/nvim-web-devicons',
    'catppuccin/nvim',
  },
  config = function()
    local tabby = require 'tabby'
    local cat = require('catppuccin.palettes').get_palette()
    local trans = require('catppuccin').options.transparent_background

    -- Make sessions keep tab layout + custom names
    vim.opt.sessionoptions:append { 'tabpages', 'globals' }

    -- Array of highlights to use
    local theme = {
      fill = { bg = trans and 'NONE' or cat.mantle, fg = cat.text },
      head = { bg = cat.base, fg = cat.text },
      current_tab = { bg = cat.blue, fg = cat.mantle },
      tab = { bg = cat.base, fg = cat.text },
    }

    tabby.setup {
      line = function(line)
        --- @module "tabby"
        --- @type (TabbyElement | string | number)[]
        return {
          hl = theme.fill,
          {
            { '  ', hl = theme.head },
            line.sep('', theme.head, theme.fill),
            hl = theme.head,
          },
          line.tabs().foreach(function(tab)
            local hl = tab.is_current() and theme.current_tab or theme.tab
            return {
              line.sep('', hl, theme.fill),
              -- tab.is_current() and '' or '󰆣',
              tab.number(),
              tab.name(),
              -- tab.close_btn '',
              line.sep('', hl, theme.fill),
              hl = hl,
              margin = ' ',
            }
          end),
          line.spacer(),
          line.wins_in_tab(line.api.get_current_tab()).foreach(function(win)
            return {
              line.sep('', theme.tab, theme.fill),
              -- win.is_current() and '' or '',
              win.buf_name(),
              line.sep('', theme.tab, theme.fill),
              hl = theme.tab,
              margin = ' ',
            }
          end),
          -- {
          --   line.sep('', theme.tail, theme.fill),
          --   { '  ', hl = theme.tail },
          -- },
        }
      end,
      -- Behavior knobs
      option = {
        tab_name = {},
        buf_name = {
          -- 'unique' = shortest path that disambiguates same-tail files
          -- alternatives: 'relative', 'tail', 'shorten'
          mode = 'unique',
        },
      },
    }
  end,
}
