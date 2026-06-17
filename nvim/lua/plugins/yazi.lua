return {
  'mikavilpas/yazi.nvim',
  event = 'VeryLazy',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  keys = {
    { '<leader>te', '<cmd>Yazi<cr>', desc = '[T]oggle [E]xplorer (yazi)' },
    { '<leader>tE', '<cmd>Yazi cwd<cr>', desc = '[T]oggle [E]xplorer at cwd (yazi)' },
  },
  opts = {
    open_for_directories = false,
    floating_window_scaling_factor = 1.0,
    yazi_floating_window_border = 'none',
    keymaps = {
      show_help = '<f1>',
    },
  },
}
