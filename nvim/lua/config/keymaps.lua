vim.api.nvim_create_user_command('Q', 'q<bang>', { bang = true, desc = 'Alias :Q to :q' })
vim.api.nvim_create_user_command('W', 'w', { desc = 'Alias :W to :w' })

local function unwrap_range(first_line, last_line)
  local config_dir = vim.uv.fs_realpath(vim.fn.stdpath 'config') or vim.fn.stdpath 'config'
  local script = vim.fs.joinpath(vim.fs.dirname(config_dir), 'scripts', 'unwrap.ts')

  if vim.fn.executable 'bun' ~= 1 then
    vim.notify('Unwrap requires bun', vim.log.levels.ERROR)
    return
  end
  if vim.fn.filereadable(script) ~= 1 then
    vim.notify('Unwrap script not found: ' .. script, vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, first_line - 1, last_line, false)
  local result = vim
    .system({ 'bun', script }, {
      stdin = table.concat(lines, '\n'),
      text = true,
    })
    :wait()

  if result.code ~= 0 then
    local message = vim.trim(result.stderr or '')
    vim.notify(message ~= '' and message or 'Unwrap failed', vim.log.levels.ERROR)
    return
  end

  vim.api.nvim_buf_set_lines(0, first_line - 1, last_line, false, vim.split(result.stdout, '\n', { plain = true }))
end

vim.api.nvim_create_user_command('Unwrap', function(args)
  unwrap_range(args.line1, args.line2)
end, {
  range = '%',
  desc = 'Unwrap hard-wrapped prose',
})

local function centered_line_move(key)
  return function()
    local keys = vim.api.nvim_replace_termcodes(key, true, false, true)
    vim.api.nvim_feedkeys(keys, 'n', false)

    local line = vim.fn.line '.'
    local last = vim.fn.line '$'
    local win_h = vim.fn.winheight(0)
    local margin = math.floor(win_h / 2)

    if line > margin and line < (last - margin) then
      vim.cmd.normal { args = { 'zz' }, bang = true }
    end
  end
end

vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

vim.keymap.set('n', '<C-d>', '<C-d>zz')
vim.keymap.set('n', '<C-u>', '<C-u>zz')
vim.keymap.set('n', '<C-f>', '<C-f>zz')
vim.keymap.set('n', '<C-b>', '<C-b>zz')
vim.keymap.set('n', '<S-Down>', centered_line_move '<S-Down>')
vim.keymap.set('n', '<S-Up>', centered_line_move '<S-Up>')

-- Cmd+C in visual mode: yank only, no cut
vim.keymap.set('v', '<D-c>', 'y')
vim.keymap.set('n', '<leader>?', function()
  require('which-key').show()
end, { desc = 'Show keymaps' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
vim.keymap.set('n', 'gl', vim.diagnostic.open_float, { desc = 'Show diagnostic float' })
vim.keymap.set('n', '[d', function()
  vim.diagnostic.jump { count = -1 }
end, { desc = 'Prev diagnostic' })
vim.keymap.set('n', ']d', function()
  vim.diagnostic.jump { count = 1 }
end, { desc = 'Next diagnostic' })

vim.fn.serverstart()

vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

vim.keymap.set('t', '<C-h>', '<C-\\><C-n><C-w><C-h>', { desc = 'Move focus left from terminal' })
vim.keymap.set('t', '<C-l>', '<C-\\><C-n><C-w><C-l>', { desc = 'Move focus right from terminal' })

vim.keymap.set('n', '<leader>yn', function()
  local name = vim.fn.expand '%:t'
  vim.fn.setreg('+', name)
  vim.notify('Copied: ' .. name)
end, { desc = 'Yank filename' })

vim.keymap.set('n', '<leader>yp', function()
  local path = vim.fn.expand '%:.'
  vim.fn.setreg('+', path)
  vim.notify('Copied: ' .. path)
end, { desc = 'Yank relative path' })

vim.keymap.set({ 'n', 'x' }, '<leader>yl', function()
  local l1, l2 = vim.fn.line '.', vim.fn.line 'v'
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  local ref = vim.fn.expand '%:.' .. ':' .. (l1 == l2 and l1 or (l1 .. '-' .. l2))
  vim.fn.setreg('+', ref)
  if vim.fn.mode():match '[vV\22]' then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
  end
  vim.notify('Copied: ' .. ref)
end, { desc = 'Yank relative path:line' })

vim.keymap.set({ 'n', 'x' }, '<leader>yg', function()
  local file = vim.fn.expand '%:p'
  local dir = vim.fn.fnamemodify(file, ':h')
  local function git(args)
    local out = vim.fn.systemlist(vim.list_extend({ 'git', '-C', dir }, args))
    return vim.v.shell_error == 0 and out[1] or nil
  end
  local root, sha, remote = git { 'rev-parse', '--show-toplevel' }, git { 'rev-parse', 'HEAD' }, git { 'remote', 'get-url', 'origin' }
  if not (root and sha and remote) then
    vim.notify('Not a git repo with origin remote', vim.log.levels.WARN)
    return
  end
  -- git@github.com:org/repo.git | https://github.com/org/repo.git | ssh://git@github.com/org/repo -> github.com/org/repo
  local base = remote:gsub('^%w+://', ''):gsub('^[^@/]+@', ''):gsub(':', '/', 1):gsub('%.git$', ''):gsub('^github%.com[^/]*', 'github.com')
  local rel = file:sub(#root + 2)
  local l1, l2 = vim.fn.line '.', vim.fn.line 'v'
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  local range = l1 == l2 and ('#L' .. l1) or ('#L' .. l1 .. '-L' .. l2)
  local url = 'https://' .. base .. '/blob/' .. sha .. '/' .. rel .. range
  vim.fn.setreg('+', url)
  if vim.fn.mode():match '[vV\22]' then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
  end
  if not git { 'branch', '-r', '--contains', sha } then
    vim.notify('Copied (HEAD not pushed, link may 404): ' .. url, vim.log.levels.WARN)
  else
    vim.notify('Copied: ' .. url)
  end
end, { desc = 'Yank GitHub permalink' })

vim.keymap.set('n', '<leader>yd', function()
  local diags = vim.diagnostic.get(0, { lnum = vim.fn.line '.' - 1 })
  if #diags == 0 then
    vim.notify 'No diagnostics on current line'
    return
  end
  local lines = vim.tbl_map(function(d)
    return d.message
  end, diags)
  local text = table.concat(lines, '\n')
  vim.fn.setreg('+', text)
  vim.notify('Copied ' .. #diags .. ' diagnostic(s)')
end, { desc = 'Yank diagnostics (line)' })

-- Move lines up/down (Option+j/k)
vim.keymap.set('n', '<A-k>', ':m .+1<CR>==', { desc = 'Move line down' })
vim.keymap.set('n', '<A-j>', ':m .-2<CR>==', { desc = 'Move line up' })
vim.keymap.set('v', '<A-k>', ":m '>+1<CR>gv=gv", { desc = 'Move selection down' })
vim.keymap.set('v', '<A-j>', ":m '<-2<CR>gv=gv", { desc = 'Move selection up' })

vim.keymap.set('n', '<leader>yD', function()
  local diags = vim.diagnostic.get(0)
  if #diags == 0 then
    vim.notify 'No diagnostics in buffer'
    return
  end
  local lines = vim.tbl_map(function(d)
    return (d.lnum + 1) .. ': ' .. d.message
  end, diags)
  local text = table.concat(lines, '\n')
  vim.fn.setreg('+', text)
  vim.notify('Copied ' .. #diags .. ' diagnostic(s)')
end, { desc = 'Yank diagnostics (buffer)' })
