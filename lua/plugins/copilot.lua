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

--- @type LazySpec | LazySpec[]
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

      -- Copilot considers any response with a user name authenticated, even
      -- when the server says `NotAuthorized`. That caused completion requests
      -- to be sent with invalid credentials and produced `[Copilot.lua] table`.
      -- Only allow suggestions after an explicit successful (`OK`) status.
      local auth = require 'copilot.auth'
      local client = require 'copilot.client'
      local api = require 'copilot.api'
      local auth_cache = { value = nil, checked_at = 0, checking = false }

      auth.is_authenticated = function(callback)
        if not client.initialized then
          return false
        end

        local now = vim.uv.now()
        if auth_cache.value ~= nil and now - auth_cache.checked_at < 30 * 1000 then
          return auth_cache.value
        end

        local lsp_client = client.get()
        if not lsp_client or auth_cache.checking then
          return false
        end

        auth_cache.checking = true
        api.check_status(lsp_client, {}, function(err, status)
          auth_cache.checking = false
          auth_cache.checked_at = vim.uv.now()
          auth_cache.value = not err and status and status.status == 'OK' and status.user ~= nil
          if callback then
            callback(err)
          end
        end)

        return false
      end

      -- Hide Copilot suggestions when the completion menu is open
      -- local cmp_ok, cmp = pcall(require, 'cmp')
      -- if cmp_ok then
      --   cmp.event:on('menu_opened', function()
      --     vim.b.copilot_suggestion_hidden = true
      --   end)
      --
      --   cmp.event:on('menu_closed', function()
      --     vim.b.copilot_suggestion_hidden = false
      --   end)
      -- end
    end,
    keys = {
      {
        '<M-y>',
        desc = 'Accept Copilot suggestion',
      },
      {
        '<leader>ec',
        toggle_copilot,
        desc = '[C]opilot',
      },
    },
  },
}
