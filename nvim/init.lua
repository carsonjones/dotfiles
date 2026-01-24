vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = true

vim.env.NODE_OPTIONS = '--max-old-space-size=16384'

-- Load local overrides before anything else
pcall(require, 'local')

require 'config.options'
require 'config.keymaps'
require 'config.autocmds'
require 'config.lazy'

-- Queue review comments (<leader>hc) for the /comments Claude skill to address.
require('comments').setup {}
