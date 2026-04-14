--- @type LazySpec
return {
  'MeanderingProgrammer/render-markdown.nvim',
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
  ft = { 'markdown' },
  ---@module 'render-markdown'
  ---@type render.md.UserConfig
  opts = {
    anti_conceal = {
      enabled = false,
    },
  },
  config = function(_, opts)
    require('render-markdown').setup(opts)

    -- Optional: Toggle markdown rendering on/off
    vim.keymap.set('n', '<leader>em', '<cmd>RenderMarkdown toggle<CR>', { desc = '[M]arkdown render' })
  end,
  keys = {
    { '<leader>em', '<cmd>RenderMarkdown toggle<CR>', desc = '[M]arkdown render' },
  },
}
