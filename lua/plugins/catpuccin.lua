return {
  'catppuccin/nvim',
  priority = 1000, -- Make sure to load this before all the other start plugins.
  name = 'catppuccin',
  config = function()
    -- Setup notify background
    vim.api.nvim_create_autocmd('ColorScheme', {
      callback = function()
        vim.api.nvim_set_hl(0, 'NotifyINFOBody', { bg = 'NONE' })
        vim.api.nvim_set_hl(0, 'NotifyINFOBorder', { bg = 'NONE' })
        vim.api.nvim_set_hl(0, 'NotifyINFOTitle', { bg = 'NONE' })
      end,
    })

    ---@diagnostic disable-next-line: missing-fields
    require('catppuccin').setup {
      flavour = 'mocha',
      transparent_background = false,
      auto_integrations = true,
      float = {
        transparent = true,
        solid = false,
      },
      integrations = {
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        treesitter = true,
        notify = true,
        mini = {
          enabled = true,
          indentscope_color = '',
        },
        -- For more plugins integrations please scroll down (https://github.com/catppuccin/nvim#integrations)
      },
    }
    -- ColorScheme
    vim.cmd.colorscheme 'catppuccin'
  end,
}
