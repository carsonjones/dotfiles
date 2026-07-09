-- Native-fzf live grep. Telescope's live_grep re-sorts/re-renders in Lua on
-- every keystroke, which crawls on large repos even with telescope-fzf-native
-- loaded. fzf-lua shells out to the real `fzf` binary instead, so <leader>sg
-- stays fast regardless of repo size.
return {
  'ibhagwan/fzf-lua',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  cmd = 'FzfLua',
  keys = {
    {
      '<leader>sg',
      function()
        require('fzf-lua').live_grep {
          rg_opts = "--column --line-number --no-heading --color=always --smart-case --follow "
            .. "-g '!*.stories.*' -g '!*.mock.*' -g '!*.mocks.*' -g '!__mocks__/*' -g '!mocks/*' "
            .. "-g '!*.test.*' -g '!*.spec.*' -g '!__snapshots__/*' -g '!*.generated.*'",
        }
      end,
      desc = '[S]earch by [G]rep (fzf)',
    },
    {
      '<leader>sa',
      function()
        require('fzf-lua').live_grep {
          rg_opts = '--column --line-number --no-heading --color=always --smart-case --follow',
        }
      end,
      desc = '[S]earch [A]ll (no filters, fzf)',
    },
  },
  opts = {
    winopts = {
      height = 0.7,
      preview = { layout = 'vertical', vertical = 'down:55%' },
    },
    -- Persist query history so <S-Up>/<S-Down> recall prior searches, like
    -- telescope's cycle_history_prev/next.
    fzf_opts = { ['--history'] = vim.fn.stdpath 'data' .. '/fzf-lua-history' },
    keymap = {
      fzf = {
        ['shift-up'] = 'prev-history',
        ['shift-down'] = 'next-history',
      },
    },
  },
}
