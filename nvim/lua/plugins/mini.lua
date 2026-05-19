return {
  'echasnovski/mini.nvim',
  event = 'VeryLazy',
  config = function()
    require('mini.ai').setup { n_lines = 500 }
    require('mini.surround').setup()
    require('mini.comment').setup()
    require('mini.cursorword').setup()

    vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
      group = vim.api.nvim_create_augroup('winbar-file-only', { clear = true }),
      callback = function()
        local bt = vim.bo.buftype
        local ft = vim.bo.filetype
        local name = vim.api.nvim_buf_get_name(0)
        if bt == '' and ft ~= 'neo-tree' and name ~= '' then
          vim.opt_local.winbar = "%#LineNr#  %f  %m%="
        else
          vim.opt_local.winbar = ''
        end
      end,
    })

    local statusline = require 'mini.statusline'
    statusline.setup {
      use_icons = vim.g.have_nerd_font,
      content = {
        active = function()
          local mode, mode_hl = MiniStatusline.section_mode { trunc_width = 120 }
          local git = MiniStatusline.section_git { trunc_width = 40 }
          local diagnostics = MiniStatusline.section_diagnostics { trunc_width = 75 }
          local search = MiniStatusline.section_searchcount { trunc_width = 75 }

          return MiniStatusline.combine_groups {
            { hl = mode_hl, strings = { mode } },
            { hl = 'MiniStatuslineDevinfo', strings = { git, diagnostics } },
            '%<',
            '%=',
            { hl = 'MiniStatuslineFileinfo', strings = { search } },
            { hl = mode_hl, strings = { '%2l:%-2v' } },
          }
        end,
      },
    }
  end,
}
