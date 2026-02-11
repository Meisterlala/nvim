--- @type LazySpec | LazySpec[]
return { -- Autoformat
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end,
      mode = '',
      desc = '[F]ormat buffer',
    },
  },
  opts = {
    notify_on_error = true,
    notify_no_formatter = true,
    format_on_save = function(bufnr)
      -- Disable "format_on_save lsp_fallback" for languages that don't
      -- have a well standardized coding style. You can add additional
      -- languages here or re-enable it for the disabled ones.
      if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
        return
      end

      -- Check for a .conformdisable file in the repository root
      local root = vim.fs.root(bufnr, { '.git', '.conformdisable' })
      if root and vim.uv.fs_stat(root .. '/.conformdisable') then
        return
      end

      local disable_filetypes = { c = true, cpp = true }
      if disable_filetypes[vim.bo[bufnr].filetype] then
        return nil
      else
        return {
          timeout_ms = 1000,
          lsp_format = 'fallback',
        }
      end
    end,
    --- @type table<string, conform.FormatterConfig>
    formatters = {
      powershell = {
        command = 'pwsh',
        args = {
          '-NoProfile',
          '-Command',
          'if (!(Get-Module -ListAvailable -Name PSScriptAnalyzer)) { Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser }; Import-Module PSScriptAnalyzer; $input | Invoke-Formatter',
        },
        stdin = true,
      },
    },

    formatters_by_ft = {
      lua = { 'stylua' },
      -- Conform can also run multiple formatters sequentially
      python = { 'ruff_fix', 'ruff_format', 'ruff_organize_imports' },
      -- All the prettier formatters
      typescript = { 'prettierd', 'prettier', stop_after_first = true },
      html = { 'prettierd', 'prettier', stop_after_first = true },
      htmlangular = { 'prettierd', 'prettier', stop_after_first = true },
      javascript = { 'prettierd', 'prettier', stop_after_first = true },
      javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
      json = { 'prettierd', 'prettier', stop_after_first = true },
      jsonc = { 'prettierd', 'prettier', stop_after_first = true },
      css = { 'prettierd', 'prettier', stop_after_first = true },
      scss = { 'prettierd', 'prettier', stop_after_first = true },
      less = { 'prettierd', 'prettier', stop_after_first = true },
      markdown = { 'prettierd', 'prettier', stop_after_first = true },
      yaml = { 'prettierd', 'prettier', stop_after_first = true },
      vue = { 'prettierd', 'prettier', stop_after_first = true },
      svelte = { 'prettierd', 'prettier', stop_after_first = true },
      astro = { 'prettierd', 'prettier', stop_after_first = true },
      graphql = { 'prettierd', 'prettier', stop_after_first = true },
      tsx = { 'prettierd', 'prettier', stop_after_first = true },
      ts = { 'prettierd', 'prettier', stop_after_first = true },
    },
  },
  init = function()
    vim.api.nvim_create_user_command('FormatDisable', function(args)
      if args.bang then
        -- FormatDisable! will disable formatting just for this buffer
        vim.b.disable_autoformat = true
      else
        vim.g.disable_autoformat = true
      end
    end, {
      desc = 'Disable autoformat-on-save',
      bang = true,
    })
    vim.api.nvim_create_user_command('FormatEnable', function()
      vim.b.disable_autoformat = false
      vim.g.disable_autoformat = false
    end, {
      desc = 'Re-enable autoformat-on-save',
    })
  end,
}
