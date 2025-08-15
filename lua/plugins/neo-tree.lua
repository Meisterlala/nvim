-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  cmd = 'Neotree',
  lazy = false, -- neo-tree will lazily load itself
  keys = {
    { 'ß', ':Neotree reveal<CR>', desc = 'NeoTree reveal', silent = true },
  },
  ---@module "neo-tree"
  ---@type neotree.Config?
  opts = {
    close_if_last_window = true, -- Close Neo-tree if it is the last window left in the tab
    filesystem = {
      hijack_netrw_behavior = 'open_default',
      use_libuv_file_watcher = true, -- Use filesystem watcht to look for changes
      window = {
        mappings = {
          ['ß'] = 'close_window',
        },
      },
    },
    window = {
      mappings = {
        ['<space>'] = nil,
        ['<tab>'] = 'toggle_node',
      },
    },
    default_component_configs = {
      file_size = {
        required_width = 50, -- Minimum width for the file size column
      },
    },
  },
}
