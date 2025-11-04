--- @type LazySpec | LazySpec[]
return {
  {
    'linux-cultist/venv-selector.nvim',
    dependencies = {
      'neovim/nvim-lspconfig',
      'mfussenegger/nvim-dap',
      'mfussenegger/nvim-dap-python', --optional
      { 'nvim-telescope/telescope.nvim', dependencies = { 'nvim-lua/plenary.nvim' } },
    },
    branch = 'regexp', -- This is the regexp branch, use this for the new version
    keys = {
      { '<leader>sv', '<cmd>VenvSelect<cr>', desc = '[S]earch Python [V]env' },
    },
    opts = {
      -- Your settings go here
    },
    ft = { 'python' },
  },
}
