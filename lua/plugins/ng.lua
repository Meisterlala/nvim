-- https://github.com/joeveiga/ng.nvim
-- Angular JS support
return {
  {
    'joeveiga/ng.nvim',
    config = function()
      local ng = require 'ng'

      -- Key mappings for Angular navigation
      vim.keymap.set('n', '<leader>dc', ng.goto_template_for_component, {
        noremap = true,
        silent = true,
        desc = 'Go to template for component',
      })
      vim.keymap.set('n', '<leader>dt', ng.goto_component_with_template_file, {
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
