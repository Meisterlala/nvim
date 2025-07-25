return { -- Highlight, edit, and navigate code
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  -- Will be needed in the future. Right now main is still broken
  -- branch = 'main',
  config = function()
    -- Add install dir to rtp
    local install_dir = vim.fn.stdpath 'data' .. '/site'
    vim.opt.rtp:prepend(install_dir)

    -- load configs module
    local configs = require 'nvim-treesitter'
    configs.setup {
      ensure_installed = { 'c', 'diff', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' },
      auto_install = true,
      -- Modules
      highlight = {
        enable = true,
      },
    }
  end,
  -- There are additional nvim-treesitter modules that you can use to interact
  -- with nvim-treesitter. You should go explore a few and see what interests you:
  --
  --    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
  --    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
  --    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
}
