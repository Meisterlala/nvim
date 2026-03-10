return {
  settings = {
    basedpyright = {
      analysis = {
        autoSearchPaths = true,
        diagnosticMode = 'openFilesOnly',
        useLibraryCodeForTypes = true,
        typeCheckingMode = 'basic',
        -- reportMissingTypeArgument = 'none',
        -- reportUnknownArgumentType = 'none',
      },
    },
  },
}
