-- https://github.com/joeveiga/ng.nvim
-- Angular JS support

return {
  {
    'joeveiga/ng.nvim',
    config = function()
      local ng = require 'ng'

      -- Ensure Treesitter is configured to include Angular
      local ok, ts_config = pcall(require, 'nvim-treesitter.configs')
      if ok then
        local ensure = ts_config.get_module 'ensure_installed' or {}
        if type(ensure) == 'table' and not vim.tbl_contains(ensure, 'angular') then
          ---@diagnostic disable-next-line: missing-fields
          ts_config.setup { ensure_installed = vim.list_extend(ensure, { 'angular' }) }
        end
      end

      -- Key mappings for Angular navigation
      vim.keymap.set('n', '<leader>dt', ng.goto_template_for_component, {
        noremap = true,
        silent = true,
        desc = 'Go to template for component',
      })
      vim.keymap.set('n', '<leader>dc', ng.goto_component_with_template_file, {
        noremap = true,
        silent = true,
        desc = 'Go to component with template file',
      })
      vim.keymap.set('n', '<leader>dT', ng.get_template_tcb, {
        noremap = true,
        silent = true,
        desc = 'Get template TCB',
      })
    end,
    keys = {
      { '<leader>dc', desc = 'Angular [C]omponent' },
      { '<leader>dt', desc = 'Angular [T]emplate' },
      { '<leader>dT', desc = 'Angular [T]ype Check Block' },
    },
  },
}
