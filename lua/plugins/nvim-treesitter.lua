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
    local configs = require 'nvim-treesitter.configs'
    ---@diagnostic disable-next-line: missing-fields
    configs.setup {
      ensure_installed = { 'c', 'diff', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' },
      auto_install = true,
      -- Modules
      highlight = {
        enable = true,

        -- Disable treesitter for large files
        disable = function(_, buf)
          local max_size_mb = 20
          local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
          if ok and stats and stats.size > (max_size_mb * 1024 * 1024) then
            return true
          end
        end,
        -- Disable vim regex
        additional_vim_regex_highlighting = false,
      },
    }
  end,
}
