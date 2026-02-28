vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = true

-- Load local overrides before anything else
pcall(require, 'local')

require 'config.options'
require 'config.keymaps'
require 'config.autocmds'
require 'config.lazy'
