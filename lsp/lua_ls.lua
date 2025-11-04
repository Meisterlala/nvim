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
    },
  },
}
