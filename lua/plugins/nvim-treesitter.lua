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

    -- Setup nvim-treesitter (new main branch uses minimal config)
    require('nvim-treesitter').setup {
      install_dir = install_dir,
      ensure_installed = {},
      auto_install = true,
    }

    -- Enable Folding
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo.foldmethod = 'expr'
    vim.opt.foldlevelstart = 99

    -- Enable Treesitter-based indentation (experimental)
    vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"

    -- Auto-attach treesitter to all buffers for highlighting
    local augroup = vim.api.nvim_create_augroup('TreesitterAutoAttach', { clear = true })
    vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter' }, {
      group = augroup,
      callback = function(args)
        local buf = args.buf
        -- Skip special buffers
        if vim.bo[buf].buftype ~= '' then
          return
        end

        -- Disable treesitter for large files (>20MB)
        local max_size_mb = 20
        local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
        if ok and stats and stats.size > (max_size_mb * 1024 * 1024) then
          return
        end

        -- Enable treesitter highlighting
        pcall(vim.treesitter.start, buf)
      end,
    })
  end,
}
