return {
  settings = {
    basedpyright = {
      analysis = {
        autoSearchPaths = true,
        diagnosticMode = 'openFilesOnly',
        useLibraryCodeForTypes = true,
        typeCheckingMode = 'standard',
        -- reportMissingTypeArgument = 'none',
        -- reportUnknownArgumentType = 'none',
      },
    },
  },
}
