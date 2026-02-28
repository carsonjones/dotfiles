return {
  '3rd/image.nvim',
  dependencies = { 'vhyrro/luarocks.nvim', priority = 1001, opts = { rocks = { 'magick' } } },
  config = function()
    require('image').setup {
      processor = 'magick_rock',
      backend = 'kitty',
      integrations = {
        markdown = { enabled = true },
        neorg = { enabled = false },
      },
      max_width = 100,
      max_height = 12,
      max_height_window_percentage = math.huge,
      max_width_window_percentage = math.huge,
    }
  end,
}
