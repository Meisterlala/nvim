--- @type LazySpec | LazySpec[]
return {
  {
    enabled = true,
    'tpope/vim-fugitive',
    cmd = { 'G', 'Git', 'Gstatus', 'Gblame', 'Gpush', 'Gpull', 'Gfetch', 'Gwrite', 'Gread' },
    config = function() end,
  },
}
