return {
  {
    'folke/snacks.nvim',
    priority = 900, -- High, but after colors
    lazy = false,
    ---@class snacks.Config
    ---@field animate? snacks.animate.Config
    ---@field bigfile? snacks.bigfile.Config
    ---@field dashboard? snacks.dashboard.Config
    ---@field dim? snacks.dim.Config
    ---@field explorer? snacks.explorer.Config
    ---@field gitbrowse? snacks.gitbrowse.Config
    ---@field image? snacks.image.Config
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
    ---@field styles? table<string, snacks.win.Config>
    ---@field image? snacks.image.Config|{}?
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
      bigfile = {
        enabled = true,
        size = 1024 * 1024 * 10, -- 10MB
      },
      dashboard = { enabled = true },
      indent = { enabled = false },
      input = { enabled = true },
      git = { enabled = false },
      image = { enabled = true },
      quickfile = { enabled = true },
    },
  },
}
