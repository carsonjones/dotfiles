return {
  'mechatroner/rainbow_csv',
  ft = { 'csv', 'tsv', 'csv_semicolon', 'csv_whitespace', 'csv_pipe', 'rfc_csv', 'rfc_semicolon' },
  init = function()
    -- Show column info on hover (set to 1 to disable)
    vim.g.disable_rainbow_hover = 0
    -- Comment prefix for CSV files
    vim.g.rainbow_comment_prefix = '#'
  end,
}
