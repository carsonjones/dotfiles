return {
  'navarasu/onedark.nvim',
  priority = 1000,
  init = function()
    require('onedark').setup {
      style = 'dark',
      colors = {
        bg0 = '#252A34',
      },
    }
    require('onedark').load()
    vim.cmd.hi 'Comment gui=none'
  end,
}
