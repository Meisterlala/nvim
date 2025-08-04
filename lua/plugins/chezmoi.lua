return {
  {
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
  },
  {
    'alker0/chezmoi.vim',
    lazy = false,
    init = function()
      -- This option is required.
      vim.g['chezmoi#use_tmp_buffer'] = true
      -- add other options here if needed.
    end,
    config = function()
      -- try env vars in this order for max compatibility
      local temp = os.getenv 'TMPDIR' or os.getenv 'TMP' or os.getenv 'TEMP' or '/tmp'
      -- Match any files in tmp that start with chezmoi-
      local pattern = temp:gsub('\\', '/') .. '/chezmoi%-[^/]+/.+'
      vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
        callback = function(args)
          local fname = args.file:gsub('\\', '/')
          if fname:match(pattern) then
            -- auto-detect the buffer format
            local type = vim.filetype.match { buf = args.buf } or ''
            vim.api.nvim_set_option_value('filetype', type .. '.chezmoitmpl', { buf = args.buf })
          end
        end,
      })
    end,
  },
}
