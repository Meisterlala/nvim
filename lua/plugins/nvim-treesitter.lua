--- @type LazySpec | LazySpec[]
return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  lazy = false,
  branch = 'main',
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
    require('nvim-treesitter').setup(config)

    -- Enable Folding
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo.foldmethod = 'expr'
    -- Set default fold level
    vim.opt.foldlevelstart = 99

    -- Enable Treesitter based indentation
    vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end,
}
