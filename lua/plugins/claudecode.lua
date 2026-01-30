--- @type LazySpec | LazySpec[]
return {
  'coder/claudecode.nvim',
  dependencies = { 'folke/snacks.nvim' },
  lazy = false,
  --- @module 'claudecode'
  --- @type PartialClaudeCodeConfig
  opts = {
    -- Server Configuration
    auto_start = true,
    log_level = 'info', -- "trace", "debug", "info", "warn", "error"

    -- Send/Focus Behavior
    -- When true, successful sends will focus the Claude terminal if already connected
    focus_after_send = false,

    -- Selection Tracking
    track_selection = true,
    visual_demotion_delay_ms = 50,

    -- Diff Integration
    ---@class ClaudeDiffOpts : ClaudeCodeDiffOptions
    diff_opts = {
      auto_close_on_accept = true,
      vertical_split = true,
      open_in_current_tab = true,
      keep_terminal_focus = false, -- If true, moves focus back to terminal after diff opens (including floating terminals)
    },
  },
  keys = {
    -- Your keymaps here
    { '<leader>cs', '<cmd>ClaudeCodeSend<cr>', mode = 'v', desc = 'Send to [C]laude' },
  },
}
