return {
  {
    'NeogitOrg/neogit',
    dependencies = {
      'nvim-lua/plenary.nvim', -- required
      'sindrets/diffview.nvim', -- optional - Diff integration

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
        graph_style = 'unicode',
        -- Change the default way of opening neogit
        kind = 'split_below',
        -- Show message with spinning animation when a git command is running.
        process_spinner = true,
        -- Used to generate URL's for branch popup action "pull request".
        git_services = {
          ['github.com'] = 'https://github.com/${owner}/${repository}/compare/${branch_name}?expand=1',
          ['bitbucket.org'] = 'https://bitbucket.org/${owner}/${repository}/pull-requests/new?source=${branch_name}&t=1',
          ['gitlab.com'] = 'https://gitlab.com/${owner}/${repository}/merge_requests/new?merge_request[source_branch]=${branch_name}',
          ['azure.com'] = 'https://dev.azure.com/${owner}/_git/${repository}/pullrequestcreate?sourceRef=${branch_name}&targetRef=${target}',
        },
        -- Allows a different telescope sorter. Defaults to 'fuzzy_with_index_bias'. The example below will use the native fzf
        -- sorter instead. By default, this function returns `nil`.
        -- telescope_sorter = function()
        --   return require('telescope').extensions.fzf.native_fzf_sorter()
        -- end,
        -- Neogit refreshes its internal state after specific events, which can be expensive depending on the repository size.
        -- Disabling `auto_refresh` will make it so you have to manually refresh the status after you open it.
        auto_refresh = true,
      }
    end,
    keys = {
      { '<leader>g', '<cmd>Neogit<cr>', desc = 'Open Neogit' },
    },
  },
}
