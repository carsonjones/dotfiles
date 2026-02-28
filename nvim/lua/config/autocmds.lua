vim.api.nvim_create_autocmd('VimEnter', {
  desc = 'Open neo-tree when nvim is opened with a directory',
  group = vim.api.nvim_create_augroup('neotree-dir-open', { clear = true }),
  once = true,
  callback = function()
    local bufname = vim.api.nvim_buf_get_name(0)
    if vim.fn.isdirectory(bufname) == 1 then
      vim.cmd 'bd'
      vim.schedule(function()
        require('lazy').load { plugins = { 'neo-tree.nvim' } }
        vim.cmd('Neotree dir=' .. bufname .. ' reveal')
      end)
    end
  end,
})

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})
