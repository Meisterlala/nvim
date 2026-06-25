--- @type LazySpec
return {
  '3rd/image.nvim',
  build = false,
  event = 'VeryLazy',
  opts = {
    backend = 'kitty',
    processor = 'magick_cli',
    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = false,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        floating_windows = false,
        filetypes = { 'markdown', 'vimwiki' },
      },
      asciidoc = {
        enabled = true,
        clear_in_insert_mode = false,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        floating_windows = false,
        filetypes = { 'asciidoc', 'adoc' },
      },
      typst = {
        enabled = true,
        filetypes = { 'typst' },
      },
      rst = {
        enabled = true,
      },
      html = {
        enabled = false,
      },
      css = {
        enabled = false,
      },
    },
    max_height_window_percentage = 50,
    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = { 'cmp_menu', 'cmp_docs', 'snacks_notif' },
    tmux_show_only_in_active_window = true,
    hijack_file_patterns = { '*.png', '*.jpg', '*.jpeg', '*.gif', '*.webp', '*.avif' },
  },
}
