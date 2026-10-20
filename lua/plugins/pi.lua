--- @type LazySpec
return {
  'carderne/pi-nvim',
  main = 'pi-nvim',
  cmd = { 'Pi', 'PiSend', 'PiSendFile', 'PiSendSelection', 'PiSendBuffer', 'PiPing', 'PiSessions' },
  opts = {
    -- Keep <leader>p available for the existing ai-provider mappings.
    set_default_keymaps = false,
  },
  keys = {
    { '<leader>aa', '<cmd>Pi<cr>', desc = '[A]sk Pi about this file' },
    -- Use : rather than <cmd> so Pi receives the visual selection's range.
    { '<leader>aa', ':Pi<cr>', mode = 'x', desc = '[A]sk Pi about selection', silent = true },
    { '<leader>af', '<cmd>PiSendFile<cr>', desc = 'Pi: send [F]ile path' },
    { '<leader>ab', '<cmd>PiSendBuffer<cr>', desc = 'Pi: send [B]uffer contents' },
    { '<leader>as', '<cmd>PiSessions<cr>', desc = 'Pi: select running [S]ession' },
    { '<leader>ap', '<cmd>PiPing<cr>', desc = 'Pi: [P]ing connection' },
  },
}
