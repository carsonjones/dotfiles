return {
  dir = '~/src/trailboss/nvim',
  enabled = vim.fn.isdirectory(vim.fn.expand '~/src/trailboss/nvim') == 1,
  dependencies = {
    {
      'rcarriga/nvim-notify',
      config = function()
        vim.notify = require 'notify'
      end,
    },
    {
      'stevearc/dressing.nvim',
      opts = {},
    },
  },
  config = function()
    require('trailboss').setup {
      source_path = '~/.local/share/trailboss/comments.jsonl',
      keys = {
        act = '<leader>tx',
        ask = '<leader>ta',
      },
    }
  end,
}
