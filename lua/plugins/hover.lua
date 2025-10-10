return {
  'lewis6991/hover.nvim',
  config = function()
    require('hover').config {
      -- Require providers
      providers = {
        'hover.providers.lsp',
        -- require('hover.providers.gh')
        -- require('hover.providers.gh_user')
        -- require('hover.providers.jira')
        -- require('hover.providers.dap')
        -- require('hover.providers.fold_preview')
        -- require('hover.providers.diagnostic')
        -- require('hover.providers.man')
        -- require('hover.providers.dictionary')
        -- require 'hover.providers.highlight'
      },
      preview_opts = {
        border = 'none',
      },
      -- Whether the contents of a currently open hover window should be moved
      -- to a :h preview-window when pressing the hover keymap.
      preview_window = true,
      title = true,
      mouse_providers = {
        'LSP',
      },
      mouse_delay = 200,
    }

    -- Setup keymaps
    vim.keymap.set('n', 'K', require('hover').open, { desc = 'hover.nvim' })
    vim.keymap.set('n', 'gK', require('hover').select, { desc = 'hover.nvim (select)' })
    vim.keymap.set('n', '<C-p>', function()
      require('hover').switch 'previous'
    end, { desc = 'hover.nvim (previous source)' })
    vim.keymap.set('n', '<C-n>', function()
      require('hover').switch 'next'
    end, { desc = 'hover.nvim (next source)' })

    -- Mouse support
    vim.keymap.set('n', '<MouseMove>', require('hover').mouse, { desc = 'hover.nvim (mouse)' })

    vim.o.mousemoveevent = true

    -- Auto open docs on hover
    vim.o.updatetime = 2000
    -- But only for LSP attached buffers
    -- vim.api.nvim_create_autocmd('LspAttach', {
    --   callback = function(args)
    --     local bufnr = args.buf
    --     vim.api.nvim_create_autocmd('CursorHold', {
    --       buffer = bufnr,
    --       callback = function()
    --         -- Check if buffer is valid
    --         if vim.api.nvim_buf_is_loaded(bufnr) then
    --           require('hover').open()
    --         end
    --       end,
    --     })
    --   end,
    -- })
  end,
}
