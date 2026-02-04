--- @type LazySpec | LazySpec[]
return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    ---@module "snacks"
    ---@class snacks.Config
    ---@field animate? snacks.animate.Config
    ---@field bigfile? snacks.bigfile.Config
    ---@field dashboard? snacks.dashboard.Config
    ---@field dim? snacks.dim.Config
    ---@field explorer? snacks.explorer.Config
    ---@field gitbrowse? snacks.gitbrowse.Config
    ---@field indent? snacks.indent.Config
    ---@field input? snacks.input.Config
    ---@field layout? snacks.layout.Config
    ---@field lazygit? snacks.lazygit.Config
    ---@field notifier? snacks.notifier.Config
    ---@field picker? snacks.picker.Config
    ---@field profiler? snacks.profiler.Config
    ---@field quickfile? snacks.quickfile.Config
    ---@field scope? snacks.scope.Config
    ---@field scratch? snacks.scratch.Config
    ---@field scroll? snacks.scroll.Config
    ---@field statuscolumn? snacks.statuscolumn.Config
    ---@field terminal? snacks.terminal.Config
    ---@field toggle? snacks.toggle.Config
    ---@field win? snacks.win.Config
    ---@field words? snacks.words.Config
    ---@field zen? snacks.zen.Config
    opts = {
      animate = { enabled = false },
      bigfile = {
        enabled = true,
        size = 1024 * 1024 * 10, -- 10MB
      },
      dashboard = {
        enabled = true,
        width = 95,
        preset = {
          keys = {
            { icon = ' ', key = 'f', desc = 'Find File', action = ':Telescope find_files' },
            { icon = ' ', key = 'n', desc = 'New File', action = ':ene | startinsert' },
            { icon = ' ', key = 'r', desc = 'Recent Files', action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = '󰒲 ', key = 'L', desc = 'Lazy', action = ':Lazy', enabled = package.loaded.lazy ~= nil },
            { icon = ' ', key = 'q', desc = 'Quit', action = ':qa' },
          },
        },

        sections = {
          { section = 'header' },
          {
            -- custom header showing NVIM version
            text = { { string.format('v%d.%d.%d', vim.version().major, vim.version().minor, vim.version().patch), align = 'center' } },
          },
          { icon = ' ', title = 'Keymaps', section = 'keys', indent = 2, padding = 1 },
          { icon = ' ', title = 'Projects', section = 'projects', limit = 8, indent = 2, padding = 1 },
          { icon = ' ', title = 'Recent Files', section = 'recent_files', indent = 2, padding = 1 },
          { section = 'startup' },
        },
      },
      indent = { enabled = false },
      input = { enabled = true },
      git = { enabled = false },
      image = { enabled = false },
      -- Might re-enable at some point
      -- quickfile = { enabled = true },
    },
  },
}
