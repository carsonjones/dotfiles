return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons',
    'MunifTanjim/nui.nvim',
  },
  lazy = true,
  cmd = { 'Neotree' },
  keys = {
    { '<leader>te', ':Neotree toggle left<CR>', desc = '[T]oggle [E]xplorer', silent = true },
  },
  opts = {
    default_component_configs = {
      git_status = {
        symbols = {
          unstaged  = '○',
          staged    = '●',
        },
      },
    },
    source_selector = {
      winbar = true,
      show_scrolled_off_parent_node = true,
    },
    hijack_netrw_behavior = 'disabled',
    window = {
      mappings = {
        ['P'] = { 'toggle_preview', config = { use_float = true, use_image_nvim = true } },
      },
    },
    git_status = {
      window = {
        mappings = {
          ['d'] = function(state)
            local node = state.tree:get_node()
            local path = node:get_id()
            vim.cmd('wincmd l')
            vim.cmd('edit ' .. vim.fn.fnameescape(path))
            vim.cmd('Gitsigns diffthis')
          end,
        },
      },
    },
    filesystem = {
      hijack_netrw_behavior = 'disabled',
      follow_current_file = { enabled = true },
      filtered_items = {
        visible = true,
        hide_dotfiles = false,
        hide_gitignored = false,
      },
      window = {
        mappings = {
          ['f'] = 'none',
        },
      },
    },
  },
}
