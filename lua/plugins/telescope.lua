local function project_files_picker(opts)
  -- Include source, config, docs, extensionless files, and dotfiles.
  -- fd still respects .gitignore/.ignore; never search Git's internal files.
  require('telescope.builtin').find_files(vim.tbl_extend('force', {
    find_command = { 'fd', '--type', 'f', '--color', 'never', '--exclude', '.git', '--strip-cwd-prefix' },
    prompt_title = 'Project files',
    hidden = true,
    follow = true,
  }, opts or {}))
end

--- @type LazySpec | LazySpec[]
return { -- Fuzzy Finder (files, lsp, etc)
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
  branch = 'master',
  dependencies = {
    { 'nvim-treesitter/nvim-treesitter' },
    'nvim-lua/plenary.nvim',
    { 'nvim-telescope/telescope-ui-select.nvim' },

    -- Useful for getting pretty icons, but requires a Nerd Font.
    { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },

    -- Native FZF sorter for telescope
    { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
  },
  config = function()
    -- See `:help telescope` and `:help telescope.setup()`
    require('telescope').setup {
      -- You can put your default mappings / updates / etc. in here
      -- pickers = {}
      extensions = {
        ['ui-select'] = {
          require('telescope.themes').get_dropdown(),
        },
      },
    }

    -- Enable Telescope extensions if they are installed
    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')
    pcall(require('telescope').load_extension, 'chezmoi')
    pcall(require('telescope').load_extension, 'notify')

    -- See `:help telescope.builtin`
    local builtin = require 'telescope.builtin'
    vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
    vim.keymap.set('n', '<leader>sb', builtin.buffers, { desc = '[S]earch [B]uffers' })
    vim.keymap.set('n', '<leader>sf', project_files_picker, { desc = '[S]earch [F]iles' })
    vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
    vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
    vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
    vim.keymap.set('n', '<leader><leader>', project_files_picker, { desc = '[ ] Find project files' })

    vim.keymap.set('n', '<leader>sF', function()
      project_files_picker { no_ignore = true, prompt_title = 'All files (including ignored)' }
    end, { desc = '[S]earch [F]iles, including ignored' })

    vim.keymap.set('n', '<leader>/', function()
      builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
        winblend = 10,
        previewer = false,
      })
    end, { desc = '[/] Fuzzily search in current buffer' })

    vim.keymap.set('n', '<leader>s/', function()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Live Grep in Open Files',
      }
    end, { desc = '[S]earch [/] in Open Files' })

    vim.keymap.set('n', '<leader>sn', function()
      builtin.find_files {
        cwd = vim.fn.stdpath 'config',
      }
    end, { desc = '[S]earch [N]eovim files' })

    vim.keymap.set('n', '<leader>sc', require('telescope').extensions.chezmoi.find_files, { desc = '[S]earch [C]hezmoi Files' })
  end,
  keys = {
    { '<leader>sh', desc = '[S]earch [H]elp' },
    { '<leader>sk', desc = '[S]earch [K]eymaps' },
    { '<leader>sb', desc = '[S]earch [B]uffers' },
    { '<leader>sf', desc = '[S]earch [F]iles' },
    { '<leader>ss', desc = '[S]earch [S]elect Telescope' },
    { '<leader>sw', desc = '[S]earch current [W]ord' },
    { '<leader>sg', desc = '[S]earch by [G]rep' },
    { '<leader>sd', desc = '[S]earch [D]iagnostics' },
    { '<leader>sr', desc = '[S]earch [R]esume' },
    { '<leader>s.', desc = '[S]earch Recent Files ("." for repeat)' },
    { '<leader><leader>', desc = '[ ] Find project files' },
    { '<leader>sF', desc = '[S]earch [F]iles, including ignored' },
    { '<leader>/', desc = '[/] Fuzzily search in current buffer' },
    { '<leader>s/', desc = '[S]earch [/] in Open Files' },
    { '<leader>sn', desc = '[S]earch [N]eovim files' },
    { '<leader>sc', desc = '[S]earch [C]hezmoi Files' },
  },
}
