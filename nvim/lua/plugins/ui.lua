return {
  {
    'rcarriga/nvim-notify',
    config = function()
      -- Normal has no bg under transparent onedark; give notify a concrete
      -- base to blend against so popups aren't pure black.
      require('notify').setup {
        background_colour = '#252A34',
        max_width = 40,
        timeout = 1500,
      }
      vim.notify = require 'notify'
    end,
  },
  {
    'stevearc/dressing.nvim',
    event = 'VeryLazy',
    opts = {},
  },
  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    dependencies = { 'MunifTanjim/nui.nvim', 'rcarriga/nvim-notify' },
    opts = {
      -- Route cmdline/messages out of the cmdline area so cmdheight=0 never
      -- forces the statusline to bounce.
      messages = { view = 'notify' },
      lsp = {
        -- Don't let LSP progress spam the message area (main insert-mode flash).
        progress = { enabled = false },
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
          ['cmp.entry.get_documentation'] = true,
        },
      },
      presets = {
        bottom_search = true,
        command_palette = true,
        long_message_to_split = true,
      },
    },
  },
}
