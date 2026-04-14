--- @type LazySpec | LazySpec[]
return { -- Useful plugin to show you pending keybinds.
  'folke/which-key.nvim',
  event = 'VeryLazy', -- Sets the loading event to 'VimEnter'
  opts = {
    -- delay between pressing a key and opening which-key (milliseconds)
    -- this setting is independent of vim.opt.timeoutlen
    delay = 300,

    preset = 'modern',
    expand = function(node)
      return not node.desc -- expand all nodes without a description
    end,

    -- Which-key automatically sets up triggers for your mappings.
    -- But you can disable this and setup the triggers manually.
    -- Check the docs for more info.
    ---@type wk.Spec
    triggers = {
      { '<auto>', mode = 'nixsotc' },
      { 'a', mode = { 'n', 'v' } },
      { 'i', mode = { 'n', 'v' } },
    },

    -- Document existing key chains
    spec = {
      { '<leader>a', group = 'Avante' },
      { '<leader>c', group = 'Code', mode = { 'n', 'x' } },
      { '<leader>ct', group = 'Tests' },
      { '<leader>d', group = 'Document' },
      { '<leader>di', group = 'Insert' },
      { '<leader>e', group = 'Editor' },
      { '<leader>g', group = 'Git' },
      { '<leader>s', group = 'Search' },
      { '<leader>S', group = 'Session' },
      { '<leader>M', hidden = true },
      { '<leader>N', hidden = true },
    },
  },
  keys = {
    {
      '<leader>?',
      function()
        require('which-key').show { global = false }
      end,
      desc = 'Buffer Local Keymaps (which-key)',
    },
  },
}
