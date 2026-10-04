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

    -- Setup nvim-treesitter
    local ts = require 'nvim-treesitter'
    ts.setup {
      install_dir = install_dir,
    }

    if not vim.list_contains(ts.get_installed 'parsers', 'regex') then
      ts.install({ 'regex' }):await(function(err)
        if err then
          vim.notify('Tree-sitter regex parser installation failed: ' .. tostring(err), vim.log.levels.ERROR)
        end
      end)
    end

    -- Enable Folding
    vim.opt.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.opt.foldmethod = 'expr'
    vim.opt.foldlevelstart = 99

    -- Auto-attach treesitter to all buffers for highlighting
    local installing = {}
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

        local ft = vim.bo[buf].filetype
        if ft == '' then
          return
        end

        -- auto_install was removed upstream; install the parser ourselves if missing
        local ts = require 'nvim-treesitter'
        local lang = vim.treesitter.language.get_lang(ft) or ft
        local installed = ts.get_installed 'parsers'
        local to_install = {}
        if not vim.list_contains(installed, lang) and vim.list_contains(ts.get_available(), lang) then
          table.insert(to_install, lang)
        end
        local ok_registry, registry = pcall(require, 'treesitter-registry')
        if ok_registry and registry.loaded and registry.loaded[lang] and registry.loaded[lang].requires then
          for _, dep in ipairs(registry.loaded[lang].requires) do
            if not vim.list_contains(installed, dep) then
              table.insert(to_install, dep)
            end
          end
        end
        if #to_install > 0 then
          if installing[lang] then
            installing[lang][buf] = true
          else
            installing[lang] = { [buf] = true }
            ts.install(to_install):await(function(err)
              local waiting = installing[lang]
              installing[lang] = nil
              if err then
                vim.notify('Tree-sitter parser installation failed: ' .. tostring(err), vim.log.levels.ERROR)
              else
                for waiting_buf in pairs(waiting) do
                  if vim.api.nvim_buf_is_valid(waiting_buf) then
                    vim.bo[waiting_buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                    pcall(vim.treesitter.start, waiting_buf)
                  end
                end
              end
            end)
          end
          return
        end

        vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        pcall(vim.treesitter.start, buf)
      end,
    })
  end,
}
