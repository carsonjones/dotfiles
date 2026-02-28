return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons',
    'MunifTanjim/nui.nvim',
  },
  lazy = true,
  keys = {
    { '<leader>te', ':Neotree toggle left<CR>', desc = '[T]oggle [E]xplorer', silent = true },
  },
  opts = {
    hijack_netrw_behavior = 'disabled',
    window = {
      mappings = {
        ['P'] = { 'toggle_preview', config = { use_float = true, use_image_nvim = true } },
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
