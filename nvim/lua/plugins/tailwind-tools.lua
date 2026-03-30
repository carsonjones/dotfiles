return {
  'luckasRanarison/tailwind-tools.nvim',
  name = 'tailwind-tools',
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
  ft = { 'html', 'css', 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'astro' },
  opts = {
    document_color = {
      enabled = true,
      kind = 'inline',
    },
    conceal = {
      enabled = false,
    },
  },
  config = function(_, opts)
    require('tailwind-tools').setup(opts)
    vim.api.nvim_create_autocmd('BufWritePre', {
      pattern = { '*.html', '*.css', '*.js', '*.ts', '*.jsx', '*.tsx', '*.astro' },
      callback = function()
        vim.cmd 'TailwindSortSync'
      end,
    })
  end,
}
