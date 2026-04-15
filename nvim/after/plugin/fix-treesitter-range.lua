-- Workaround for Neovim 0.12.1 treesitter range() bug
-- The built-in get_range() crashes when a nil node is passed through.
-- This wraps it with a pcall to prevent the error wall on markdown files.
-- TODO: Remove after upgrading to nvim 0.12.2+

local ok, ts = pcall(require, 'vim.treesitter')
if not ok or not ts then
  return
end

local original_get_range = ts.get_range
if not original_get_range then
  return
end

---@diagnostic disable-next-line: duplicate-set-field
ts.get_range = function(node, source, metadata)
  if node == nil then
    return { 0, 0, 0, 0, 0, 0 }
  end
  local success, result = pcall(original_get_range, node, source, metadata)
  if success then
    return result
  end
  return { 0, 0, 0, 0, 0, 0 }
end
