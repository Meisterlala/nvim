--- @type LazySpec | LazySpec[]
return {
  'tpope/vim-sleuth', -- Detect tabstop and shiftwidth automatically
  event = 'BufReadPre', -- Load before reading buffer
}
