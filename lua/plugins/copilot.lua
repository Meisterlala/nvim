return {
  {
    enabled = false,
    'github/copilot.vim',
    config = function()
      vim.cmd 'Copilot setup'
      -- Set up Copilot with custom options
      vim.g.copilot_filetypes = {
        ['*'] = true, -- Enable for all
        ['lua'] = true, -- Enable for Lua
      }
    end,
  },
}
