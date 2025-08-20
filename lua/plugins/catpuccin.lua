return {
  'catppuccin/nvim',
  priority = 1000, -- Make sure to load this before all the other start plugins.
  name = 'catppuccin',
  config = function()
    ---@diagnostic disable-next-line: missing-fields
    require('catppuccin').setup {
      flavour = 'mocha',
      transparent_background = false,
      auto_integrations = true,
      float = {
        transparent = false,
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
      },
    }

    -- Overwrite some highlights
    vim.api.nvim_create_autocmd('ColorScheme', {
      pattern = 'catppuccin',
      callback = function()
        -- vim.api.nvim_set_hl(0, 'Normal', { bg = 'NONE' })
        -- vim.api.nvim_set_hl(0, 'NonText', { bg = 'NONE' })
        vim.api.nvim_set_hl(0, 'RenderMarkdownCode', { bg = 'NONE' })
      end,
    })

    -- ColorScheme
    vim.cmd.colorscheme 'catppuccin'
  end,
}
