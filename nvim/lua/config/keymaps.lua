vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
vim.keymap.set('n', '<leader>?', function() require('which-key').show() end, { desc = 'Show keymaps' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
vim.keymap.set('n', 'gl', vim.diagnostic.open_float, { desc = 'Show diagnostic float' })

vim.fn.serverstart()

vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

vim.keymap.set('t', '<C-h>', '<C-\\><C-n><C-w><C-h>', { desc = 'Move focus left from terminal' })
vim.keymap.set('t', '<C-l>', '<C-\\><C-n><C-w><C-l>', { desc = 'Move focus right from terminal' })

vim.keymap.set('n', '<leader>yn', function()
  local name = vim.fn.expand('%:t')
  vim.fn.setreg('+', name)
  vim.notify('Copied: ' .. name)
end, { desc = 'Yank filename' })

vim.keymap.set('n', '<leader>yp', function()
  local path = vim.fn.expand('%:.')
  vim.fn.setreg('+', path)
  vim.notify('Copied: ' .. path)
end, { desc = 'Yank relative path' })

vim.keymap.set('n', '<leader>yd', function()
  local diags = vim.diagnostic.get(0, { lnum = vim.fn.line('.') - 1 })
  if #diags == 0 then
    vim.notify('No diagnostics on current line')
    return
  end
  local lines = vim.tbl_map(function(d) return d.message end, diags)
  local text = table.concat(lines, '\n')
  vim.fn.setreg('+', text)
  vim.notify('Copied ' .. #diags .. ' diagnostic(s)')
end, { desc = 'Yank diagnostics (line)' })

vim.keymap.set('n', '<leader>yD', function()
  local diags = vim.diagnostic.get(0)
  if #diags == 0 then
    vim.notify('No diagnostics in buffer')
    return
  end
  local lines = vim.tbl_map(function(d)
    return (d.lnum + 1) .. ': ' .. d.message
  end, diags)
  local text = table.concat(lines, '\n')
  vim.fn.setreg('+', text)
  vim.notify('Copied ' .. #diags .. ' diagnostic(s)')
end, { desc = 'Yank diagnostics (buffer)' })
