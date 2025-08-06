return {
  enabled = false,
  'TheLeoP/powershell.nvim',
  config = function()
    ---@type powershell.user_config
    local opts = {
      bundle_path = vim.fn.stdpath 'data' .. '/mason/packages/powershell-editor-services',
    }
    require('powershell').setup(opts)
  end,
}
