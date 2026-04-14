--- @type LazySpec | LazySpec[]
return {
  'lewis6991/hover.nvim',
  event = 'VeryLazy',
  keys = {
    { 'K', desc = 'Hover documentation' },
    { 'gK', desc = 'Hover select provider' },
    { '<C-p>', mode = 'n', desc = 'Hover previous source' },
    { '<C-n>', mode = 'n', desc = 'Hover next source' },
    { '<leader>eh', desc = '[H]over' },
  },
  config = function()
    local hover = require 'hover'
    hover.setup {
      providers = {
        'hover.providers.lsp',
        'hover.providers.diagnostic',
        'hover.providers.dap',
        {
          module = 'hover.providers.dictionary',
          enabled = function(bufnr)
            return #vim.lsp.get_clients { bufnr = bufnr } == 0
          end,
        },
      },
      preview_opts = { border = 'none' },
      preview_window = true,
      title = false,
      mouse_providers = {
        'hover.providers.lsp',
        'hover.providers.diagnostic',
        'hover.providers.dap',
      },
      mouse_delay = 200,
    }

    vim.keymap.set('n', 'K', hover.open, { desc = 'hover.nvim' })
    vim.keymap.set('n', '<C-p>', function() hover.switch 'previous' end, { desc = 'hover.nvim (previous source)' })
    vim.keymap.set('n', '<C-n>', function() hover.switch 'next' end, { desc = 'hover.nvim (next source)' })

    local hover_enabled = false
    vim.o.mousemoveevent = false

    vim.keymap.set('n', '<leader>eh', function()
      hover_enabled = not hover_enabled
      vim.o.mousemoveevent = hover_enabled
      if hover_enabled then
        vim.keymap.set('n', '<MouseMove>', hover.mouse, { desc = 'hover.nvim (mouse)' })
      else
        pcall(vim.keymap.del, 'n', '<MouseMove>')
      end
      vim.notify('Hover ' .. (hover_enabled and 'Enabled' or 'Disabled'))
    end, { desc = '[H]over' })

    vim.api.nvim_create_autocmd('CursorHold', {
      group = vim.api.nvim_create_augroup('hover_auto_open', { clear = true }),
      callback = function()
        if not hover_enabled or vim.bo.buftype ~= '' then return end
        local bufnr = vim.api.nvim_get_current_buf()
        if vim.b[bufnr].hover_preview and vim.api.nvim_win_is_valid(vim.b[bufnr].hover_preview) then return end
        pcall(hover.open)
      end,
    })

    -- Keep the "Invalid window id" fix
    local util = require('hover.util')
    local original_open = util.open_floating_preview
    util.open_floating_preview = function(...)
      local winid = original_open(...)
      if not winid or not vim.api.nvim_win_is_valid(winid) then
        return winid
      end

      local original_set = vim.api.nvim_set_option_value
      vim.api.nvim_set_option_value = function(name, val, opts)
        if opts and opts.win == winid then
          if not vim.api.nvim_win_is_valid(winid) then return end
        end
        return original_set(name, val, opts)
      end
      
      return winid
    end
  end,
}
