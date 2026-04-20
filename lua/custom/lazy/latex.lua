return {
  {
    '3rd/image.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    ft = { 'tex', 'markdown' },
    opts = {
      backend = 'kitty',
      integrations = {
        markdown = { enabled = false },
      },
      max_width_window_percentage = 100,
      max_height_window_percentage = 100,
      kitty_method = 'normal',
      window_overlap_clear_enabled = true,
    },
  },
}
