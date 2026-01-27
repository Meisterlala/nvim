--- @type LazySpec | LazySpec[]
return {
  {
    'xvzc/chezmoi.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('chezmoi').setup {
        edit = { watch = true, force = false },
        events = {
          on_open = { notification = { enable = true, msg = 'Opened chezmoi file' } },
          on_watch = { notification = { enable = false } },
          on_apply = { notification = { enable = true, msg = 'Applied' } },
        },
        telescope = { select = { '<CR>' } },
      }

      local chezmoi_dir = vim.env.HOME .. '/.local/share/chezmoi'

      vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
        group = vim.api.nvim_create_augroup('chezmoi_auto_edit', { clear = true }),
        callback = function(ev)
          if vim.fn.executable 'chezmoi' == 0 then
            return
          end

          local filepath = vim.api.nvim_buf_get_name(ev.buf)
          if filepath == '' then
            return
          end

          -- If already in chezmoi source dir, enable auto-apply
          if vim.startswith(filepath, chezmoi_dir .. '/') then
            vim.schedule(function()
              require('chezmoi.commands.__edit').watch(ev.buf)
            end)
            return
          end

          -- Check if file is managed and switch to source
          vim.schedule(function()
            local cmd = string.format('chezmoi source-path %s 2>/dev/null', vim.fn.shellescape(filepath))
            local handle = io.popen(cmd)
            if not handle then
              return
            end

            local source_path = handle:read '*l'
            handle:close()

            if source_path and source_path ~= '' then
              require('chezmoi.commands.__edit').execute {
                targets = { filepath },
                args = { '--watch' },
              }
            end
          end)
        end,
      })
    end,
  },
  {
    'alker0/chezmoi.vim',
    lazy = false,
    init = function()
      vim.g['chezmoi#use_tmp_buffer'] = true
    end,
    config = function()
      local temp = os.getenv 'TMPDIR' or os.getenv 'TMP' or os.getenv 'TEMP' or '/tmp'
      local pattern = temp:gsub('\\', '/') .. '/chezmoi%-[^/]+/.+'

      vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
        group = vim.api.nvim_create_augroup('chezmoi_tmpl', { clear = true }),
        callback = function(args)
          local fname = args.file:gsub('\\', '/')
          if fname:match(pattern) then
            local filetype = vim.filetype.match { buf = args.buf } or ''
            vim.bo[args.buf].filetype = filetype .. '.chezmoitmpl'
          end
        end,
      })
    end,
  },
}
