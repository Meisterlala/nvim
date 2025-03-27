return {
  'catppuccin/nvim',
  priority = 1000, -- Make sure to load this before all the other start plugins.
  name = 'catppuccin',
  config = function()
    ---@diagnostic disable-next-line: missing-fields
    require('catppuccin').setup {
      flacour = 'frappe',
      transparent_background = false,
    }
    -- ColorScheme
    vim.cmd.colorscheme 'catppuccin'
  end,
}
