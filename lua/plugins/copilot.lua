local function toggle_copilot()
  local disabled = require('copilot.client').is_disabled()

  if disabled then
    require('copilot.command').enable()
    vim.notify('Copilot enabled', vim.log.levels.INFO, { title = 'Copilot' })
  else
    require('copilot.command').disable()
    vim.notify('Copilot disabled', vim.log.levels.INFO, { title = 'Copilot' })
  end
end

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

      -- Hide Copilot suggestions when the completion menu is open
      local cmp_ok, cmp = pcall(require, 'cmp')
      if cmp_ok then
        cmp.event:on('menu_opened', function()
          -- vim.b.copilot_suggestion_hidden = true
        end)

        cmp.event:on('menu_closed', function()
          -- vim.b.copilot_suggestion_hidden = false
        end)
      end

      -- Rebind <M-y> to <C-y>, if there are no suggestions
      local copilot_suggestion = require 'copilot.suggestion'
      vim.keymap.set('i', '<M-y>', function()
        if copilot_suggestion.is_visible() then
          copilot_suggestion.accept()
        else
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-y>', true, false, true), 'n', true)
        end
      end, { desc = 'Accept Copilot suggestion' })
    end,
    keys = {
      {
        '<M-y>',
        desc = 'Accept Copilot suggestion',
      },
      {
        '<Leader>C',
        toggle_copilot,
        desc = '[C]opilot toggle',
      },
    },
  },
}
