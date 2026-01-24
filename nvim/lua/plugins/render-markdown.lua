return {
  'MeanderingProgrammer/render-markdown.nvim',
  ft = { 'markdown', 'mdx' },
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.nvim' },
  opts = {
    win_options = {
      concealcursor = {
        rendered = 'nc',
      },
    },
    patterns = {
      markdown_inline = {
        disable = true,
        directives = {
          { id = 8, name = 'conceal' },
          { id = 13, name = 'conceal' },
          { id = 14, name = 'conceal' },
          { id = 15, name = 'conceal' },
        },
      },
    },
    heading = {
      icons = {},
      backgrounds = {},
    },
    link = {
      enabled = false,
    },
    pipe_table = {
      style = 'none',
    },
    bullet = {
      icons = { '⏺', '○', '◆', '◇' },
    },
    strikethrough = {
      enabled = false,
    },
  },
}
