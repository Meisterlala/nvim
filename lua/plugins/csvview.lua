-- Automatically enable CsvView for CSV files
vim.api.nvim_create_autocmd('BufReadPost', {
  pattern = '*.csv',
  callback = function(arg)
    local stat = vim.uv.fs_stat(arg.file)
    local max_size_mb = 10
    if stat and stat.size < (1024 * 1024 * max_size_mb) then
      vim.cmd 'CsvViewEnable'
    end
  end,
})

--- @type LazySpec | LazySpec[]
return {
  'hat0uma/csvview.nvim',
  ---@module "csvview"
  ---@type CsvView.Options
  opts = {
    parser = {
      comments = { '#', '//' },
      async_chunksize = 20,
    },
    view = {
      display_mode = 'border',
    },
    keymaps = {
      -- Text objects for selecting fields
      textobject_field_inner = { 'if', mode = { 'o', 'x' } },
      textobject_field_outer = { 'af', mode = { 'o', 'x' } },
      -- Excel-like navigation:
      -- Use <Tab> and <S-Tab> to move horizontally between fields.
      -- Use <Enter> and <S-Enter> to move vertically between rows and place the cursor at the end of the field.
      -- Note: In terminals, you may need to enable CSI-u mode to use <S-Tab> and <S-Enter>.
      jump_next_field_end = { '<Tab>', mode = { 'n', 'v' } },
      jump_prev_field_end = { '<S-Tab>', mode = { 'n', 'v' } },
      jump_next_row = { '<Enter>', mode = { 'n', 'v' } },
      jump_prev_row = { '<S-Enter>', mode = { 'n', 'v' } },
    },
  },
  cmd = { 'CsvViewEnable', 'CsvViewDisable', 'CsvViewToggle' },
}
