--- @type LazySpec | LazySpec[]
return {
  'lewis6991/hover.nvim',
  event = 'VeryLazy',
  keys = {
    { 'K', desc = 'Hover documentation' },
    { 'gK', desc = 'Hover select provider' },
    { '<C-p>', mode = 'n', desc = 'Hover previous source' },
    { '<C-n>', mode = 'n', desc = 'Hover next source' },
    -- { '<MouseMove>', mode = 'n', desc = 'Hover mouse' },
    { '<leader>H', desc = 'Toggle [H]over' },
  },
  config = function()
    local hover = require 'hover'
    hover.setup {
      -- Require providers
      --- @type (string|Hover.Config.Provider)[]
      providers = {
        'hover.providers.lsp',
        'hover.providers.diagnostic',
        'hover.providers.dap',
        'hover.providers.dictionary',
        -- require('hover.providers.gh')
        -- require('hover.providers.gh_user')
        -- require('hover.providers.jira')
        -- require('hover.providers.fold_preview')
        -- require('hover.providers.man')
        -- require('hover.providers.dictionary')
        -- 'hover.providers.highlight',
      },
      preview_opts = {
        border = 'none',
      },
      -- Whether the contents of a currently open hover window should be moved
      -- to a :h preview-window when pressing the hover keymap.
      preview_window = true,
      title = false,
      mouse_providers = {
        -- 'hover.providers.highlight',
        'hover.providers.lsp',
        'hover.providers.diagnostic',
        'hover.providers.dap',
      },
      mouse_delay = 200,
    }

    -- Setup keymaps
    vim.keymap.set('n', 'K', hover.open, { desc = 'hover.nvim' })
    -- vim.keymap.set('n', 'gK', function()
    --   hover.select {}
    -- end, { desc = 'hover.nvim (select)' })
    vim.keymap.set('n', '<C-p>', function()
      hover.switch 'previous'
    end, { desc = 'hover.nvim (previous source)' })
    vim.keymap.set('n', '<C-n>', function()
      hover.switch 'next'
    end, { desc = 'hover.nvim (next source)' })

    local hover_enabled = true
    vim.keymap.set('n', '<leader>H', function()
      hover_enabled = not hover_enabled
      vim.notify('Hover ' .. (hover_enabled and 'Enabled' or 'Disabled'))
    end, { desc = 'Toggle [H]over' })

    -- Mouse support
    -- vim.keymap.set('n', '<MouseMove>', require('hover').mouse, { desc = 'hover.nvim (mouse)' })

    -- vim.o.mousemoveevent = true

    -- Auto open docs on hover, but only for LSP-attached buffers
    vim.api.nvim_create_autocmd('CursorHold', {
      group = vim.api.nvim_create_augroup('hover_auto_open', { clear = true }),
      callback = function()
        if not hover_enabled then
          return
        end
        local bufnr = vim.api.nvim_get_current_buf()
        -- Only trigger automatically if a hover window isn't already open
        local hover_win = vim.b[bufnr].hover_preview
        if hover_win and vim.api.nvim_win_is_valid(hover_win) then
          return
        end
        if vim.api.nvim_buf_is_loaded(bufnr) and #vim.lsp.get_clients { bufnr = bufnr } > 0 then
          require('hover').open()
        end
      end,
    })
  end,
}
