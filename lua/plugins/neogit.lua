--- @type LazySpec | LazySpec[]
return {
  {
    'NeogitOrg/neogit',
    dependencies = {
      'nvim-lua/plenary.nvim', -- required
      {
        'sindrets/diffview.nvim',
        opts = {
          -- The default view is 'diff2' which shows the diff of the current file in the left pane and the diff of the staged file in
          -- the right pane. You can change this to 'diff1' to show only the current file's diff.
          view = {
            default = {
              layout = 'diff2_horizontal',
            },
          },
        },
      },

      -- Only one of these is needed.
      'nvim-telescope/telescope.nvim', -- optional
    },
    config = function()
      require('neogit').setup {
        -- Hides the hints at the top of the status buffer
        disable_hint = false,
        -- Offer to force push when branches diverge
        prompt_force_push = true,
        -- Changes what mode the Commit Editor starts in. `true` will leave nvim in normal mode, `false` will change nvim to
        -- insert mode, and `"auto"` will change nvim to insert mode IF the commit message is empty, otherwise leaving it in
        -- normal mode.
        disable_insert_on_commit = 'auto',
        -- When enabled, will watch the `.git/` directory for changes and refresh the status buffer in response to filesystem
        filewatcher = {
          interval = 1000,
          enabled = true,
        },
        -- "ascii"   is the graph the git CLI generates
        -- "unicode" is the graph like https://github.com/rbong/vim-flog
        -- "kitty"   is the graph like https://github.com/isakbm/gitgraph.nvim - use https://github.com/rbong/flog-symbols if you don't use Kitty
        graph_style = 'kitty',
        -- Change the default way of opening neogit
        kind = 'split_below',
        -- Show message with spinning animation when a git command is running.
        process_spinner = false,
        -- Used to generate URL's for branch popup action "pull request".
        -- Allows a different telescope sorter. Defaults to 'fuzzy_with_index_bias'. The example below will use the native fzf
        -- sorter instead. By default, this function returns `nil`.
        -- telescope_sorter = function()
        --   return require('telescope').extensions.fzf.native_fzf_sorter()
        -- end,
        -- Neogit refreshes its internal state after specific events, which can be expensive depending on the repository size.
        --
        -- The time after which an output console is shown for slow running commands
        console_timeout = 5000,
        -- Disabling `auto_refresh` will make it so you have to manually refresh the status after you open it.
        auto_refresh = true,

        -- Each Integration is auto-detected through plugin presence, however, it can be disabled by setting to `false`
        integrations = {
          -- If enabled, use telescope for menu selection rather than vim.ui.select.
          -- Allows multi-select and some things that vim.ui.select doesn't.
          telescope = true,
          -- Neogit only provides inline diffs. If you want a more traditional way to look at diffs, you can use `diffview`.
          -- The diffview integration enables the diff popup.
          --
          -- Requires you to have `sindrets/diffview.nvim` installed.
          diffview = true,

          -- If enabled, uses fzf-lua for menu selection. If the telescope integration
          -- is also selected then telescope is used instead
          -- Requires you to have `ibhagwan/fzf-lua` installed.
          fzf_lua = true,

          -- If enabled, uses mini.pick for menu selection. If the telescope integration
          -- is also selected then telescope is used instead
          -- Requires you to have `echasnovski/mini.pick` installed.
          mini_pick = false,

          -- If enabled, uses snacks.picker for menu selection. If the telescope integration
          -- is also selected then telescope is used instead
          -- Requires you to have `folke/snacks.nvim` installed.
          snacks = false,
          gitsigns = true,
        },

        mappings = {
          commit_editor = {
            ['q'] = 'Close',
            ['<c-s>'] = 'Submit',
            ['<c-c>'] = 'Abort',
            ['<m-p>'] = 'PrevMessage',
            ['<m-n>'] = 'NextMessage',
            ['<m-r>'] = 'ResetMessage',
          },
          commit_editor_I = {
            ['<c-s>'] = 'Submit',
            ['<c-c>'] = 'Abort',
          },
          rebase_editor = {
            ['p'] = 'Pick',
            ['r'] = 'Reword',
            ['e'] = 'Edit',
            ['s'] = 'Squash',
            ['f'] = 'Fixup',
            ['x'] = 'Execute',
            ['d'] = 'Drop',
            ['b'] = 'Break',
            ['q'] = 'Close',
            ['<cr>'] = 'OpenCommit',
            ['gk'] = 'MoveUp',
            ['gj'] = 'MoveDown',
            ['<c-s>'] = 'Submit',
            ['<c-c>'] = 'Abort',
            ['[c'] = 'OpenOrScrollUp',
            [']c'] = 'OpenOrScrollDown',
          },
          rebase_editor_I = {
            ['<c-s>'] = 'Submit',
            ['<c-c>'] = 'Abort',
          },
          finder = {
            ['<cr>'] = 'Select',
            ['<c-c>'] = 'Close',
            ['<esc>'] = 'Close',
            ['<c-n>'] = 'Next',
            ['<c-p>'] = 'Previous',
            ['<down>'] = 'Next',
            ['<up>'] = 'Previous',
            ['<tab>'] = 'InsertCompletion',
            ['<c-y>'] = 'CopySelection',
            ['<space>'] = 'MultiselectToggleNext',
            ['<s-space>'] = 'MultiselectTogglePrevious',
            ['<c-j>'] = 'NOP',
            ['<ScrollWheelDown>'] = 'ScrollWheelDown',
            ['<ScrollWheelUp>'] = 'ScrollWheelUp',
            ['<ScrollWheelLeft>'] = 'NOP',
            ['<ScrollWheelRight>'] = 'NOP',
            ['<LeftMouse>'] = 'MouseClick',
            ['<2-LeftMouse>'] = 'NOP',
          },
          -- Setting any of these to `false` will disable the mapping.
          popup = {
            ['?'] = 'HelpPopup',
            ['A'] = 'CherryPickPopup',
            ['d'] = 'DiffPopup',
            ['M'] = 'RemotePopup',
            ['P'] = 'PushPopup',
            ['X'] = 'ResetPopup',
            ['Z'] = 'StashPopup',
            ['i'] = 'IgnorePopup',
            ['t'] = 'TagPopup',
            ['b'] = 'BranchPopup',
            ['B'] = 'BisectPopup',
            ['w'] = 'WorktreePopup',
            ['c'] = 'CommitPopup',
            ['f'] = 'FetchPopup',
            ['l'] = 'LogPopup',
            ['m'] = 'MergePopup',
            ['p'] = 'PullPopup',
            ['r'] = 'RebasePopup',
            ['v'] = 'RevertPopup',
          },
          status = {
            ['j'] = 'MoveDown',
            ['k'] = 'MoveUp',
            ['o'] = 'OpenTree',
            ['q'] = 'Close',
            ['I'] = 'InitRepo',
            ['1'] = 'Depth1',
            ['2'] = 'Depth2',
            ['3'] = 'Depth3',
            ['4'] = 'Depth4',
            ['Q'] = 'Command',
            ['<tab>'] = 'Toggle',
            ['za'] = 'Toggle',
            ['zo'] = 'OpenFold',
            ['x'] = 'Discard',
            ['s'] = 'Stage',
            ['S'] = 'StageUnstaged',
            ['<c-s>'] = 'StageAll',
            ['u'] = 'Unstage',
            ['K'] = 'Untrack',
            ['U'] = 'UnstageStaged',
            ['y'] = 'ShowRefs',
            ['$'] = 'CommandHistory',
            ['Y'] = 'YankSelected',
            ['<c-r>'] = 'RefreshBuffer',
            ['<cr>'] = 'GoToFile',
            ['<s-cr>'] = 'PeekFile',
            ['<c-v>'] = 'VSplitOpen',
            ['<c-x>'] = 'SplitOpen',
            ['<c-t>'] = 'TabOpen',
            ['{'] = 'GoToPreviousHunkHeader',
            ['}'] = 'GoToNextHunkHeader',
            ['[c'] = 'OpenOrScrollUp',
            [']c'] = 'OpenOrScrollDown',
            ['<c-k>'] = 'PeekUp',
            ['<c-j>'] = 'PeekDown',
            ['<c-n>'] = 'NextSection',
            ['<c-p>'] = 'PreviousSection',
          },
        },
      }
    end,
    keys = {
      { '<leader>g', '<cmd>Neogit<cr>', desc = 'Open Neogit' },
    },
  },
}
