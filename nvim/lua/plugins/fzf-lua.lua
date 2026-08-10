-- Native fzf for file/grep search. Telescope re-sorts/re-renders in Lua on
-- every keystroke, which crawls on large repos even with telescope-fzf-native
-- loaded. fzf-lua shells out to the real `fzf` binary instead, so <leader>sf
-- and <leader>sg stay fast regardless of repo size.
return {
  'ibhagwan/fzf-lua',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  cmd = 'FzfLua',
  keys = {
    {
      '<leader>sf',
      function()
        require('fzf-lua').files {
          -- matches FZF_DEFAULT_COMMAND (zsh/zshrc) so results agree with the
          -- `vf` CLI alias; keep the main/code exclude to dodge the symlink
          -- loop into ~/src noted in telescope.lua.
          fd_opts = "--color=never --type f --type d --hidden --follow --exclude .git --exclude '**/main/code'",
        }
      end,
      desc = '[S]earch [F]iles (fzf)',
    },
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
    {
      '<leader>sw',
      function()
        require('fzf-lua').grep_cword {
          rg_opts = "--column --line-number --no-heading --color=always --smart-case --follow "
            .. "-g '!*.stories.*' -g '!*.mock.*' -g '!*.mocks.*' -g '!__mocks__/*' -g '!mocks/*' "
            .. "-g '!*.test.*' -g '!*.spec.*' -g '!__snapshots__/*' -g '!*.generated.*'",
        }
      end,
      desc = '[S]earch current [W]ord (fzf)',
    },
    {
      '<leader>sw',
      function()
        require('fzf-lua').grep_visual {
          rg_opts = "--column --line-number --no-heading --color=always --smart-case --follow "
            .. "-g '!*.stories.*' -g '!*.mock.*' -g '!*.mocks.*' -g '!__mocks__/*' -g '!mocks/*' "
            .. "-g '!*.test.*' -g '!*.spec.*' -g '!__snapshots__/*' -g '!*.generated.*'",
        }
      end,
      mode = 'x',
      desc = '[S]earch selection (fzf)',
    },
    {
      '<leader>s*',
      function()
        require('fzf-lua').grep_curbuf { search = vim.fn.expand '<cword>' }
      end,
      desc = '[S]earch current word in file (fzf)',
    },
    {
      '<leader>sh',
      function()
        require('fzf-lua').grep_curbuf { search = vim.fn.expand '<cword>' }
      end,
      desc = '[S]earch [H]ere (current word in file, fzf)',
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
