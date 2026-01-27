--- @type LazySpec | LazySpec[]
return { -- Highlight, edit, and navigate code
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  lazy = false,
  -- Will be needed in the future. Right now main is still broken
  -- branch = 'main',
  branch = 'master',
  config = function()
    -- Add install dir to rtp
    local install_dir = vim.fn.stdpath 'data' .. '/site'
    vim.opt.rtp:prepend(install_dir)

    -- load configs module
    --- @class TSConfig
    local config = {
      install_dir = install_dir,
      ensure_installed = {},
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

      -- Experimental indent
      indent = {
        enable = true,
      },
    }

    -- Enable folds
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    -- Set default fold level
    vim.opt.foldlevelstart = 99

    require('nvim-treesitter.configs').setup(config)
  end,
}
