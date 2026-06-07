--- @type LazySpec
return {
  dir = vim.fn.stdpath 'config' .. '/local/ai-commit',
  name = 'ai-commit',
  ft = 'gitcommit',
  cmd = { 'AICommit', 'AICommitModel' },
  dependencies = { 'nvim-lua/plenary.nvim', 'ai-provider' },
  opts = {},
  config = function(_, opts)
    require('ai-commit').setup(opts)
  end,
}
