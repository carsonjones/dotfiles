return {
  {
    'leath-dub/snipe.nvim',
    keys = {
      { 'gb', function() require('snipe').open_buffer_menu() end, desc = 'Snipe buffer menu' },
    },
    opts = {
      ui = { position = 'topleft', border = 'rounded', max_path_width = 1 },
      sort = 'default',
    },
  },
  {
    'MagicDuck/grug-far.nvim',
    cmd = 'GrugFar',
    keys = {
      { '<leader>fr', function() require('grug-far').open { prefills = { search = vim.fn.expand '<cword>' } } end, desc = 'Find & replace' },
      { '<leader>fr', function() require('grug-far').with_visual_selection() end, mode = 'v', desc = 'Find & replace selection' },
    },
    opts = {},
  },
  {
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    keys = {
      { '<leader>a', function() require('harpoon'):list():add() end, desc = 'Harpoon add' },
      { '<C-e>', function() local h = require('harpoon') h.ui:toggle_quick_menu(h:list()) end, desc = 'Harpoon menu' },
      { '<leader>1', function() require('harpoon'):list():select(1) end, desc = 'Harpoon 1' },
      { '<leader>2', function() require('harpoon'):list():select(2) end, desc = 'Harpoon 2' },
      { '<leader>3', function() require('harpoon'):list():select(3) end, desc = 'Harpoon 3' },
      { '<leader>4', function() require('harpoon'):list():select(4) end, desc = 'Harpoon 4' },
    },
    opts = {},
  },
  { 'folke/persistence.nvim', event = 'BufReadPre', opts = {} },
  { 'tpope/vim-sleuth', event = 'BufReadPost' },
  { 'folke/todo-comments.nvim', event = 'BufReadPost', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },
  { 'lukas-reineke/indent-blankline.nvim', main = 'ibl', event = 'BufReadPost', opts = {} },
  { 'akinsho/git-conflict.nvim', version = '*', event = 'BufReadPost', opts = {} },
}
