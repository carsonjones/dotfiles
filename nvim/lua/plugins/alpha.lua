return {
  'goolord/alpha-nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    local alpha = require 'alpha'
    local dashboard = require 'alpha.themes.dashboard'

    dashboard.section.header.val = {
      ' ▐▄▄▄       ▐ ▄ ·▄▄▄▄•▄▄▄ .',
      '  ·██ ▄█▀▄ •█▌▐█▪▀·.█▌▀▄.▀·',
      '▪▄ ██▐█▌.▐▌▐█▐▐▌▄█▀▀▀•▐▀▀▪▄',
      '▐▌▐█▌▐█▌.▐▌██▐█▌█▌▪▄█▀▐█▄▄▌',
      ' ▀▀▀• ▀█▄▀▪▀▀ █▪·▀▀▀ • ▀▀▀ ',
    }

    dashboard.section.buttons.val = {
      dashboard.button('e', '  File tree', function()
        require('lazy').load { plugins = { 'neo-tree.nvim' } }
        vim.cmd 'Neotree reveal'
      end),
      dashboard.button('f', '  Find file', ':Telescope find_files<CR>'),
      dashboard.button('r', '  Recent files', ':Telescope oldfiles<CR>'),
      dashboard.button('g', '  Live grep', ':Telescope live_grep<CR>'),
      dashboard.button('c', '  Config', ':e ~/.config/nvim/init.lua<CR>'),
      dashboard.button('q', '  Quit', ':qa<CR>'),
    }

    alpha.setup(dashboard.opts)
  end,
}
