return {
  'coder/claudecode.nvim',
  dependencies = { 'folke/snacks.nvim' },
  config = true,
  opts = {
    terminal_cmd = 'claude --settings \'{"autoApplyEdits":true}\'',
    terminal = {
      split_side = 'right',
      split_width_percentage = 0.30,
    },
  },
  init = function()
    vim.api.nvim_create_autocmd('BufWinEnter', {
      callback = function(ev)
        local name = vim.api.nvim_buf_get_name(ev.buf)
        if name:match('%(proposed%)') or name:match('%(NEW FILE %- proposed%)') or name:match('%(New%)') then
          vim.schedule(function()
            vim.cmd('ClaudeCodeDiffAccept')
          end)
        end
      end,
    })
  end,
  keys = {
    { '<leader>ac', '<cmd>ClaudeCode<cr>', desc = 'Toggle Claude' },
    { '<leader>af', '<cmd>ClaudeCodeFocus<cr>', desc = 'Focus Claude' },
    { '<leader>as', '<cmd>ClaudeCodeSend<cr>', mode = 'v', desc = 'Send selection' },
    { '<leader>ab', '<cmd>ClaudeCodeAdd %<cr>', desc = 'Add buffer' },
  },
}
