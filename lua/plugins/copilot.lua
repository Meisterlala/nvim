return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    config = function()
      require('copilot').setup {
        suggestion = {
          enabled = true,
          auto_trigger = true,
          keymap = {
            accept = '<M-y>',
            accept_word = false,
            accept_line = false,
            next = '<M-n>',
            prev = '<M-p>',
            dismiss = false,
          },
        },
        panel = { enabled = false },
        filetypes = {
          ['*'] = true,
        },
      }

      local cmp_ok, cmp = pcall(require, 'cmp')
      if cmp_ok then
        cmp.event:on('menu_opened', function()
          vim.b.copilot_suggestion_hidden = true
        end)

        cmp.event:on('menu_closed', function()
          vim.b.copilot_suggestion_hidden = false
        end)
      end
    end,
    keys = {
      {
        '<M-y>',
        desc = 'Accept Copilot suggestion',
      },
      {
        '<Leader>C',
        function()
          require('copilot.suggestion').toggle_auto_trigger()
        end,
        desc = '[C]opilot auto trigger',
      },
    },
  },
}
