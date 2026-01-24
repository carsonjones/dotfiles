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
          -- `vf` CLI alias. Per-project excludes (e.g. ~/main/code -> ~/src)
          -- live in that project's .ignore, which fd reads on its own.
          fd_opts = '--color=never --type f --type d --hidden --follow --exclude .git',
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
  -- One history file per picker (keyed off the picker's resume key), so
  -- <leader>sg recalls greps and <leader>sf recalls file queries instead of
  -- both sharing one list.
  init = function()
    vim.g.fzf_history_dir = vim.fn.stdpath 'data' .. '/fzf-lua-history'
  end,
  opts = {
    winopts = {
      height = 0.9,
      preview = { layout = 'vertical', vertical = 'down:70%' },
      -- fzf only appends to --history on accept, so a query you <Esc> out of is
      -- lost. fzf-lua remembers it either way (for `resume`), so on close we
      -- append it ourselves and <S-Up> can recall it next time.
      on_close = function()
        local cfg = require 'fzf-lua.config'
        local query = cfg.__resume_data and cfg.__resume_data.last_query
        local histfile = vim.tbl_get(cfg, '__resume_data', 'opts', 'fzf_opts', '--history')
        if type(query) ~= 'string' or query == '' or type(histfile) ~= 'string' then
          return
        end
        local lines = vim.fn.filereadable(histfile) == 1 and vim.fn.readfile(histfile) or {}
        if lines[#lines] == query then
          return
        end
        table.insert(lines, query)
        -- match fzf's default --history-size so the file can't grow forever
        while #lines > 1000 do
          table.remove(lines, 1)
        end
        vim.fn.writefile(lines, histfile)
      end,
    },
    keymap = {
      -- builtin keymaps are bound nvim-side and win over the fzf ones, so the
      -- default preview-page-up/down on <S-Up>/<S-Down> has to go for history
      -- recall to reach fzf. Preview scroll stays on <M-S-Up>/<M-S-Down>.
      builtin = {
        ['<S-up>'] = false,
        ['<S-down>'] = false,
      },
      fzf = {
        ['shift-up'] = 'prev-history',
        ['shift-down'] = 'next-history',
      },
    },
  },
}
