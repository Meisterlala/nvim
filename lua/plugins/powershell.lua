--- @type LazySpec | LazySpec[]
return {
  enabled = true,
  ft = { 'ps1' },
  'TheLeoP/powershell.nvim',
  ---@type powershell.user_config
  opts = {
    bundle_path = vim.fn.stdpath 'data' .. '/mason/packages/powershell-editor-services',
    settings = {
      powershell = {
        enableProfileLoading = false,
        enableConsoleRepl = true,
      },
    },
  },
}
