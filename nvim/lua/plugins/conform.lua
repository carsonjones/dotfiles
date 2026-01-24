return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>cf',
      function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end,
      mode = '',
      desc = '[C]ode [F]ormat buffer',
    },
  },
  opts = {
    notify_on_error = false,
    format_on_save = function(bufnr)
      local disable_filetypes = { c = true, cpp = true }
      local ft = vim.bo[bufnr].filetype

      if disable_filetypes[ft] then
        return { timeout_ms = 500, lsp_format = 'never' }
      end

      local biome_fts = { typescript = true, javascript = true }
      if biome_fts[ft] then
        local path = vim.api.nvim_buf_get_name(bufnr)
        local biome_root = vim.fn.expand('~/src/home/jonze')
        if path:sub(1, #biome_root) == biome_root then
          return { timeout_ms = 500, formatters = { 'biome' } }
        end
      end

      return { timeout_ms = 3000, lsp_format = 'fallback' }
    end,
    formatters_by_ft = {
      lua = { 'stylua' },
      go = { 'goimports', 'gofumpt' },
      python = { 'ruff_fix', 'ruff_format' },
      javascript = { 'prettier' },
      typescript = { 'prettier' },
      astro = { 'prettier' },
    },
  },
}
