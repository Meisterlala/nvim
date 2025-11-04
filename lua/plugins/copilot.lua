local function toggle_copilot()
  local disabled = require('copilot.client').is_disabled()

  if disabled then
    require('copilot.command').enable()
    vim.notify('Copilot enabled', vim.log.levels.INFO, { title = 'Copilot' })
  else
    require('copilot.command').disable()

    -- Rebind <M-y> to <C-y>, so that auto-complete falls back to nvim-cmp
    vim.api.nvim_set_keymap('i', '<M-y>', '<C-y>', { silent = true })

    vim.notify('Copilot disabled', vim.log.levels.INFO, { title = 'Copilot' })
  end
end

return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    dependencies = { 'copilotlsp-nvim/copilot-lsp' },
    event = { 'InsertEnter', 'VeryLazy' },
    config = function()
      require('copilot').setup {
        suggestion = {
          enabled = true,
          auto_trigger = true,
          keymap = {
            accept = '<M-y>',
            -- You can add additional keymaps below if needed
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
        toggle_copilot,
        desc = '[C]opilot toggle',
      },
    },
  },
}
