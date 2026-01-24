return {
  'luckasRanarison/tailwind-tools.nvim',
  name = 'tailwind-tools',
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
  ft = { 'html', 'css', 'javascript', 'typescript', 'javascriptreact', 'typescriptreact', 'astro' },
  opts = {
    document_color = {
      enabled = false,
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
      callback = function(args)
        -- only sort when the tailwind LSP is actually attached, else
        -- non-tailwind projects spam "tailwind-language-server is not running"
        if next(vim.lsp.get_clients { bufnr = args.buf, name = 'tailwindcss' }) then
          vim.cmd 'TailwindSortSync'
        end
      end,
    })
  end,
}
