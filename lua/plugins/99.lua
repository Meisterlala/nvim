--- @type LazySpec
return {
  'ThePrimeagen/99',
  dependencies = {
    'hrsh7th/nvim-cmp',
  },
  config = function()
    local _99 = require '99'

    _99.setup {
      model = 'openai/gpt-5.3-codex',
      completion = {
        source = 'cmp',
        custom_rules = {},
        files = {},
      },
      md_files = { 'AGENT.md' },
    }

    vim.keymap.set('v', '9', function()
      _99.visual()
    end, { desc = '[9]9 Open prompt from visual selection' })

    vim.keymap.set({ 'n', 'v' }, '<leader>9s', function()
      _99.stop_all_requests()
    end, { desc = '[9]9 [S]top all requests' })

    vim.keymap.set('n', '<leader>9i', function()
      _99.info()
    end, { desc = '[9]9 [I]nfo panel' })

    vim.keymap.set('n', '<leader>9f', function()
      _99.search()
    end, { desc = '[9]9 [F]ind code via AI search' })

    vim.keymap.set('n', '<leader>9l', function()
      _99.view_logs()
    end, { desc = '[9]9 View [L]ogs' })
  end,
  keys = {
    { '9', mode = 'v', desc = '[9]9 Open prompt from visual selection' },
    { '<leader>9s', mode = { 'n', 'v' }, desc = '[9]9 [S]top all requests' },
    { '<leader>9i', mode = 'n', desc = '[9]9 [I]nfo panel' },
    { '<leader>9f', mode = 'n', desc = '[9]9 [F]ind code via AI search' },
    { '<leader>9l', mode = 'n', desc = '[9]9 View [L]ogs' },
  },
}
