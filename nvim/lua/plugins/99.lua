return {
  'ThePrimeagen/99',
  enabled = false,
  config = function()
    local _99 = require '99'
    _99.setup {
      provider = _99.ClaudeCodeProvider,
      completion = {
        source = 'cmp',
      },
      md_files = { 'AGENT.md' },
    }
    vim.keymap.set('v', '<leader>9v', _99.visual)
    vim.keymap.set('v', '<leader>9s', _99.stop_all_requests)
  end,
}
