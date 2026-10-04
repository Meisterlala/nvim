--- @type LazySpec | LazySpec[]
return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-neotest/nvim-nio',
    'nvim-lua/plenary.nvim',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',
    'nvim-neotest/neotest-python',
  },
  opts = {
    adapters = {
      ['neotest-python'] = {
        runner = 'pytest',
        args = { '--rootdir', 'tests' },
      },
    },
  },
  config = function(_, opts)
    local adapters = {}
    for name, config in pairs(opts.adapters or {}) do
      table.insert(adapters, require(name)(config))
    end
    opts.adapters = adapters
    require('neotest').setup(opts)
  end,
  keys = {
    { '<leader>ctt', function() require('neotest').run.run() end,                   desc = '[T]est nearest' },
    { '<leader>ctf', function() require('neotest').run.run(vim.fn.expand('%')) end, desc = '[T]est [F]ile' },
    { '<leader>cts', function() require('neotest').summary.toggle() end,            desc = '[T]est [S]ummary' },
    { '<leader>cto', function() require('neotest').output_panel.toggle() end,       desc = '[T]est [O]utput' },
  },
}
