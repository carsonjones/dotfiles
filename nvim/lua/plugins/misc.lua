return {
  {
    'MagicDuck/grug-far.nvim',
    cmd = 'GrugFar',
    keys = {
      { '<leader>fr', function() require('grug-far').open { prefills = { search = vim.fn.expand '<cword>' } } end, desc = 'Find & replace' },
      { '<leader>fr', function() require('grug-far').with_visual_selection() end, mode = 'v', desc = 'Find & replace selection' },
    },
    opts = {},
  },
  { 'tpope/vim-sleuth', event = 'BufReadPost' },
  { 'folke/todo-comments.nvim', event = 'BufReadPost', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },
  { 'lukas-reineke/indent-blankline.nvim', main = 'ibl', event = 'BufReadPost', opts = {} },
  { 'akinsho/git-conflict.nvim', version = '*', event = 'BufReadPost', opts = {} },
}
