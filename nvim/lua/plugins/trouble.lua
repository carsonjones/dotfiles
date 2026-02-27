return {
  'folke/trouble.nvim',
  opts = {},
  cmd = 'Trouble',
  keys = {
    { '<leader>xx', '<cmd>Trouble diagnostics toggle<cr>', desc = 'Diagnostics' },
    { '<leader>xX', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>', desc = 'Buffer Diagnostics' },
    { '<leader>xr', '<cmd>Trouble lsp_references toggle<cr>', desc = 'LSP References' },
    { '<leader>xd', '<cmd>Trouble lsp_definitions toggle<cr>', desc = 'LSP Definitions' },
    { '<leader>xq', '<cmd>Trouble qflist toggle<cr>', desc = 'Quickfix List' },
  },
}
