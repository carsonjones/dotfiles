return {
  {
    'zbirenbaum/copilot.lua',
    event = 'InsertEnter',
    cmd = 'Copilot',
    config = function()
      require('copilot').setup {
        suggestion = {
          enabled = true,
          auto_trigger = true,
          keymap = {
            accept = '<C-j>',
            dismiss = '<C-]>',
          },
        },
        panel = { enabled = false },
      }
    end,
  },
}
