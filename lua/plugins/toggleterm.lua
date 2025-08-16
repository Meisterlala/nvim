return {
  {
    'akinsho/toggleterm.nvim',
    version = '*',
    config = function()
      require('toggleterm').setup {
        -- open_mapping = [[<leader>t]],
        insert_mappings = false,
        shade_terminals = false,
        direction = 'horizontal',
        persist_size = true,
        close_on_exit = true,
      }
      -- Keymaps
      vim.keymap.set('n', '<leader>t', '<Cmd>ToggleTerm<CR>', { desc = 'Open [T]erminal' })
    end,
    keys = {
      { '<leader>t', nil, desc = 'Open [T]erminal' },
    },
  },
}
