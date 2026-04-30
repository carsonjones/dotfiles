return {
  'MeanderingProgrammer/render-markdown.nvim',
  ft = { 'markdown', 'mdx' },
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.nvim' },
  opts = {
    heading = {
      icons = {},
      backgrounds = {},
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
