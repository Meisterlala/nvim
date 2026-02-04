return {
  -- cmd = { ... },
  -- filetypes = { ... },
  -- capabilities = {},
  settings = {
    Lua = {
      completion = {
        callSnippet = 'Replace',
      },
      codeLens = {
        enable = true,
      },
      hint = {
        enable = true,
        setType = true,
      },
      telemetry = {
        enable = false,
      },

      -- https://luals.github.io/wiki/settings/#diagnosticsseverity
      diagnostics = {
        severity = {
          ['missing-fields'] = 'Hint',
        },
      },

      -- Load types from Neovim runtime and installed plugins
      workspace = {
        library = {
          vim.env.VIMRUNTIME,
          '${3rd}/luv/library',
          -- Add lazy.nvim plugin directories
          -- vim.fn.stdpath 'data' .. '/lazy',
        },
        checkThirdParty = false,
      },
    },
  },
}
