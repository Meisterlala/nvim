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

            RenderMarkdownCode = { bg = colors.mantle },
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

      --- Function to modify existing highlight groups
      local function mod_hl(hl_name, opts)
        local is_ok, hl_def = pcall(vim.api.nvim_get_hl_by_name, hl_name, true)
        if is_ok then
          for k, v in pairs(opts) do
            hl_def[k] = v
          end
          vim.api.nvim_set_hl(0, hl_name, hl_def)
        end
      end
      local c = require('catppuccin.palettes').get_palette()
      --- Autocmd to Appply my custom highlights when colorscheme is loaded
      vim.api.nvim_create_autocmd('ColorScheme', {
        pattern = 'catppuccin',
        callback = function()
          -- mod_hl('AvantePopupHint', { fg = c.red, bg = 'NONE', force = true, blend = 10 })
          -- vim.api.nvim_set_hl(0, 'AvantePopupHint', { fg = c.red, bg = 'NONE', force = true, blend = 110 })
        end,
      })

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
