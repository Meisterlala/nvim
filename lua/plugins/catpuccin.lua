--- @type LazySpec | LazySpec[]
return {
  {
    'catppuccin/nvim',
    priority = 2000, -- Make sure to load this before all the other start plugins.
    name = 'catppuccin',
    config = function()
      local trans = true

      ---@diagnostic disable-next-line: missing-fields
      require('catppuccin').setup {
        flavour = 'macchiato',
        transparent_background = trans,
        auto_integrations = true,
        float = {
          transparent = false,
          solid = false,
        },
        -- Set Custom Highlights
        custom_highlights = function(colors)
          return {

            -- RenderMarkdownCode = { bg = colors.surface0 },
            -- NeoTreeNormal = { bg = colors.none },

            MiniStatuslineFilename = { fg = colors.text, bg = trans and colors.none or colors.mantle },
            MiniStatuslineInactive = { fg = colors.blue, bg = trans and colors.none or colors.mantle },

            AvanteTitle = { fg = colors.base, bg = colors.lavender },
            AvanteReversedTitle = { fg = colors.lavender, bg = colors.none },
            AvanteSubtitle = { fg = colors.base, bg = colors.peach },
            AvanteReversedSubtitle = { fg = colors.peach, bg = colors.none },
            AvanteThirdTitle = { fg = colors.base, bg = colors.blue },
            AvanteReversedThirdTitle = { fg = colors.blue, bg = colors.none },
            AvantePromptInput = { fg = colors.text, bg = colors.none },
            AvantePromptInputBorder = { fg = colors.text, bg = colors.none },
            AvanteSidebarNormal = { fg = colors.text, bg = colors.none },
            AvanteToBeDeleted = { fg = colors.red, bg = colors.none },

            TelescopeNormal = { fg = colors.text, bg = colors.none },
            TelescopeBorder = { fg = colors.text, bg = colors.none },
            TelescopeTitle = { fg = colors.text, bg = colors.none },
          }
        end,

        -- Enalble integrations (they are on by default anyway)
        integrations = {
          avante = true,
          nvimtree = true,
          diffview = true,
          gitsigns = true,
          markdown = true,
          mini = {
            enabled = true,
            indentscope_color = '',
          },
          neotree = true,
          neogit = true,
          noice = true,
          cmp = true,
          copilot_vim = true,
          native_lsp = {
            enabled = true,
            virtual_text = {
              errors = { 'italic' },
              hints = { 'italic' },
              warnings = { 'italic' },
              information = { 'italic' },
              ok = { 'italic' },
            },
            underlines = {
              errors = { 'underline' },
              hints = { 'underline' },
              warnings = { 'underline' },
              information = { 'underline' },
              ok = { 'underline' },
            },
            inlay_hints = {
              background = true,
            },
          },
          notify = true,
          nvim_surround = true,
          treesitter = true,
          telescope = {
            enabled = true,
          },
          which_key = true,
        },
      }
      -- Load the ColorScheme
      vim.cmd.colorscheme 'catppuccin'
    end,
  },

  {
    'xiyaowong/transparent.nvim',
    lazy = false,
    enabled = true,
    priority = 1900,
    config = function()
      require('transparent').setup {
        -- table: default groups
        groups = {},
        -- table: additional groups that should be cleared
        extra_groups = {
          'AvantePopupHint',
        },
        -- table: groups you don't want to clear
        exclude_groups = {},
        -- function: code to be executed after highlight groups are cleared
        -- Also the user event "TransparentClear" will be triggered
        on_clear = function() end,
      }
    end,
  },
}
