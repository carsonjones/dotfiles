return {
  'lewis6991/gitsigns.nvim',
  event = 'BufReadPre',
  opts = {
    diff_opts = { internal = true },
    word_diff = true,
    signs = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
    on_attach = function(bufnr)
      vim.api.nvim_set_hl(0, 'GitSignsAddInline', { bg = '#344030' })
      vim.api.nvim_set_hl(0, 'GitSignsDeleteInline', { bg = '#4a2f2f' })
      vim.api.nvim_set_hl(0, 'GitSignsChangeInline', { bg = '#2f3448' })
      local gs = require 'gitsigns'
      local map = function(mode, l, r, desc)
        vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
      end

      map('n', ']h', gs.next_hunk, 'Next hunk')
      map('n', '[h', gs.prev_hunk, 'Prev hunk')
      map('n', '<leader>hs', gs.stage_hunk, 'Stage hunk')
      map('v', '<leader>hs', function() gs.stage_hunk { vim.fn.line '.', vim.fn.line 'v' } end, 'Stage hunk')
      map('n', '<leader>hr', gs.reset_hunk, 'Reset hunk')
      map('v', '<leader>hr', function() gs.reset_hunk { vim.fn.line '.', vim.fn.line 'v' } end, 'Reset hunk')
      map('n', '<leader>hS', gs.stage_buffer, 'Stage buffer')
      map('n', '<leader>hu', gs.undo_stage_hunk, 'Undo stage hunk')
      map('n', '<leader>hp', gs.preview_hunk, 'Preview hunk')
      map('n', '<leader>hb', function() gs.blame_line { full = true } end, 'Blame line')
      map('n', '<leader>hd', gs.diffthis, 'Diff this')
    end,
  },
}
