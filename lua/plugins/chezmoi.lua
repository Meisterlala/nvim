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

      -- Encrypted source files (chezmoi's "encrypted_" attribute) are ciphertext on
      -- disk, so they can't be opened/watched like plain source files: chezmoi.nvim's
      -- own edit/watch just reads and writes the source file verbatim, which would
      -- edit the raw ciphertext. These helpers decrypt/encrypt through `chezmoi`
      -- itself instead of reimplementing age, and never touch a plaintext temp file
      -- on disk (unlike `chezmoi edit`), so decrypted content only ever lives in the
      -- nvim buffer.
      local function is_encrypted(source_path)
        return vim.fn.fnamemodify(source_path, ':t'):match '^encrypted_' ~= nil
      end

      local function encrypt_and_apply(buf, source_path)
        local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'

        local enc = vim.system({ 'chezmoi', 'encrypt', '-o', source_path }, { stdin = content, text = true }):wait()
        if enc.code ~= 0 then
          vim.notify('chezmoi: encrypt failed\n' .. (enc.stderr or ''), vim.log.levels.ERROR)
          return
        end

        local app = vim.system({ 'chezmoi', 'apply', '--source-path', source_path }, { text = true }):wait()
        if app.code ~= 0 then
          vim.notify('chezmoi: apply failed\n' .. (app.stderr or ''), vim.log.levels.ERROR)
          return
        end

        vim.bo[buf].modified = false
        vim.notify('chezmoi: applied ' .. vim.fn.fnamemodify(source_path, ':t'), vim.log.levels.INFO)
      end

      -- Opening the source file directly: it currently holds raw ciphertext, so
      -- replace it with a virtual buffer holding the decrypted content.
      ---@param old_buf number
      ---@param source_path string
      ---@param target_path string? already known target path; resolved via `chezmoi target-path` if omitted
      local function edit_encrypted_source(old_buf, source_path, target_path)
        if not target_path then
          local target = vim.system({ 'chezmoi', 'target-path', source_path }, { text = true }):wait()
          if target.code ~= 0 then
            vim.notify('chezmoi: could not resolve target path\n' .. (target.stderr or ''), vim.log.levels.ERROR)
            return
          end
          target_path = vim.trim(target.stdout)
        end

        local buf_name = 'chezmoi://' .. vim.fn.fnamemodify(target_path, ':~')
        local existing = vim.fn.bufnr(buf_name)
        if existing ~= -1 and existing ~= old_buf then
          vim.api.nvim_set_current_buf(existing)
          vim.api.nvim_buf_delete(old_buf, { force = true })
          return
        end

        local dec = vim.system({ 'chezmoi', 'decrypt', source_path }, { text = true }):wait()
        if dec.code ~= 0 then
          vim.notify('chezmoi: decrypt failed\n' .. (dec.stderr or ''), vim.log.levels.ERROR)
          return
        end

        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, buf_name)
        vim.bo[buf].buftype = 'acwrite'
        vim.bo[buf].bufhidden = 'wipe' -- don't let decrypted content linger in a hidden buffer
        vim.bo[buf].swapfile = false
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split((dec.stdout:gsub('\n$', '')), '\n', { plain = true }))
        vim.bo[buf].modified = false

        local ft = vim.filetype.match { filename = target_path } or ''
        vim.bo[buf].filetype = source_path:match '%.tmpl%.age$' and (ft .. '.chezmoitmpl') or ft

        vim.api.nvim_create_autocmd('BufWriteCmd', {
          buffer = buf,
          callback = function()
            encrypt_and_apply(buf, source_path)
          end,
        })

        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_delete(old_buf, { force = true })
      end

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
              if is_encrypted(filepath) then
                edit_encrypted_source(ev.buf, filepath)
              else
                require('chezmoi.commands.__edit').watch(ev.buf)
              end
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
              if is_encrypted(source_path) then
                edit_encrypted_source(ev.buf, source_path, filepath)
              else
                require('chezmoi.commands.__edit').execute {
                  targets = { filepath },
                  args = { '--watch' },
                }
              end
            end
          end)
        end,
      })
    end,
  },
  {
    'alker0/chezmoi.vim',
    event = 'VeryLazy', -- Only needed for template syntax
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
