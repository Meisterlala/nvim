-- Recommended session options
vim.o.sessionoptions = 'blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions'

return {
  'rmagatti/auto-session',
  lazy = false,

  ---enables autocomplete for opts
  ---@module "auto-session"
  ---@type AutoSession.Config
  opts = {
    root_dit = vim.fn.expand '~/.vim/swapdir',
    suppressed_dirs = { '~/', '~/Downloads', '/' },
    close_filetypes_on_save = { 'checkhealth' }, -- Buffers with matching filetypes will be closed before saving
    session_lens = {
      mappings = {
        -- Mode can be a string or a table, e.g. {"i", "n"} for both insert and normal mode
        delete_session = { 'i', '<C-D>' },
        alternate_session = { 'i', '<C-S>' },
        copy_session = { 'i', '<C-Y>' },
      },

      -- Telescope only: If load_on_setup is false, make sure you use `:SessionSearch` to open the picker as it will initialize everything first
      load_on_setup = true,
    },
  },
  keys = {
    -- Will use Telescope if installed or a vim.ui.select picker otherwise
    { '<leader>So', '<cmd>SessionSearch<CR>', desc = 'Session [O]pen' },
    { '<leader>Ss', '<cmd>SessionSave<CR>', desc = '[S]ave Session' },
    { '<leader>St', '<cmd>SessionToggleAutoSave<CR>', desc = '[T]oggle autosave' },
  },
}
