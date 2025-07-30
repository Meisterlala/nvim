return {
  'xvzc/chezmoi.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    -- Auto run chezmoi apply
    --  e.g. ~/.local/share/chezmoi/*
    vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
      pattern = { vim.fn.expand '~/.local/share/chezmoi/' .. '*' },
      callback = function(ev)
        local bufnr = ev.buf
        local edit_watch = function()
          require('chezmoi.commands.__edit').watch(bufnr)
        end
        vim.schedule(edit_watch)
      end,
    })

    require('chezmoi').setup {
      {
        edit = {
          watch = true,
          force = false,
        },
        events = {
          on_open = {
            notification = {
              enable = true,
              msg = 'Opened a chezmoi-managed file',
              opts = {},
            },
          },
          on_watch = {
            notification = {
              enable = true,
              msg = 'This file will be automatically applied',
              opts = {},
            },
          },
          on_apply = {
            notification = {
              enable = true,
              msg = 'Successfully applied',
              opts = {},
            },
          },
        },
        telescope = {
          select = { '<CR>' },
        },
      },
    }
  end,
}
