--- @type LazySpec
return {
  'seblyng/roslyn.nvim',
  ft = { 'cs', 'vb' },
  ---@module 'roslyn.config'
  ---@type RoslynNvimConfig
  opts = {
    extensions = {
      razor = { enabled = false },
    },
  },
}
