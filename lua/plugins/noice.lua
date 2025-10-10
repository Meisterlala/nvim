return {
  'folke/noice.nvim',
  event = 'VeryLazy',
  config = function()
    require('noice').setup {
      lsp = {
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
          ['cmp.entry.get_documentation'] = true, -- requires hrsh7th/nvim-cmp
        },
      },
      -- you can enable a preset for easier configuration
      presets = {
        -- bottom_search = true, -- use a classic bottom cmdline for search
        command_palette = true, -- position the cmdline and popupmenu together
        long_message_to_split = true, -- long messages will be sent to a split
        inc_rename = false, -- enables an input dialog for inc-rename.nvim
        lsp_doc_border = false, -- add a border to hover docs and signature help
      },
      routes = {
        {
          filter = { event = 'msg_show', kind = 'search_count' },
          opts = { skip = true },
        },
        {
          -- Hide "-- INSERT --", "-- VISUAL --", etc.
          filter = { event = 'msg_showmode' },
          opts = { skip = true },
        },
        {
          filter = {
            event = 'msg_show',
            kind = '',
            find = 'written',
          },
          opts = { skip = true },
        },
      },
    }
    vim.keymap.set({ 'n', 'i', 's' }, '<c-f>', function()
      if not require('noice.lsp').scroll(4) then
        return '<c-f>'
      end
    end, { silent = true, expr = true })

    vim.keymap.set({ 'n', 'i', 's' }, '<c-b>', function()
      if not require('noice.lsp').scroll(-4) then
        return '<c-b>'
      end
    end, { silent = true, expr = true })
  end,
  dependencies = {
    -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
    'MunifTanjim/nui.nvim',
    -- OPTIONAL:
    --   `nvim-notify` is only needed, if you want to use the notification view.
    --   If not available, we use `mini` as the fallback
    {
      'rcarriga/nvim-notify',
      opts = {
        fps = 1,
        timeout = 3000,
        stages = 'static',
      },
      keys = {
        {
          '<leader>sm',
          function()
            require('telescope').extensions.notify.notify()
          end,
          desc = '[S]earch [M]essages and Notifications',
        },
      },
    },
  },
  keys = {
    {
      '<c-f>',
      desc = 'Scroll Documentation',
    },
    {
      '<c-b>',
      desc = 'Scroll Documentation reverse',
    },
  },
}
