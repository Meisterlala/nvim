return {
  'catppuccin/nvim',
  priority = 2000, -- Make sure to load this before all the other start plugins.
  name = 'catppuccin',
  config = function()
    local trans = true

    ---@diagnostic disable-next-line: missing-fields
    require('catppuccin').setup {
      flavour = 'mocha',
      transparent_background = trans,
      auto_integrations = true,
      float = {
        transparent = true,
        solid = false,
      },
      -- Set Custom Highlights
      custom_highlights = function(colors)
        return {
          -- RenderMarkdownCode = { bg = colors.none },
          -- NeoTreeNormal = { bg = colors.none },

          MiniStatuslineFilename = { fg = colors.text, bg = trans and colors.none or colors.mantle },
          MiniStatuslineInactive = { fg = colors.blue, bg = trans and colors.none or colors.mantle },

          AvanteTitle = { fg = colors.base, bg = colors.lavender },
          AvanteSubtitle = { fg = colors.base, bg = colors.peach },
          AvanteThirdtitle = { fg = colors.base, bg = colors.blue },
        }
      end,

      -- Enalble integrations (they are on by default anyway)
      integrations = {
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
}
