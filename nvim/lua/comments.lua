-- comments.nvim
--
-- Borrowed from trailboss.lua. Instead of launching an agent, each comment is
-- appended to a per-repo JSONL queue. A Claude agent later runs the `/comments`
-- skill, which reads the queue, addresses each note, and archives the file.
--
-- Unlike a diff viewer, this works on ANY line of ANY file -- committed,
-- unchanged, or untracked -- with nothing else running.
--
--   normal mode  <leader>hc  -> comment on the current line
--   visual mode  <leader>hc  -> comment on the selected range
--   normal mode  <leader>hx  -> remove all queued comments for the current file
--
-- Lines with a queued comment get a subtle dot in the sign column, refreshed
-- on buffer enter and whenever you add or clear a comment.
--
-- Queue:   ~/.local/share/comments/<repo-slug>.jsonl   (one record per line)
-- Read by: the `/comments` Claude Code skill.

local M = {}

M.config = {
  dir = vim.fn.expand("~/.local/share/comments"),
  keys = {
    comment = "<leader>hc",
    remove = "<leader>hx",
  },
  sign = "•",
  -- Above gitsigns (default 6) so the comment dot stays visible on changed
  -- lines. Widen with `signcolumn = "auto:2"` to see both at once.
  sign_priority = 20,
}

local ns = vim.api.nvim_create_namespace("comments")

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "comments" })
end

-- Git repo root for a path's directory; falls back to cwd so notes still queue
-- outside a repo. Must match how the /comments skill resolves it.
local function repo_root_for(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  local out = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
    return out[1]
  end
  return vim.fn.getcwd()
end

-- Deterministic per-repo filename: "/Users/cjones/main" -> "%Users%cjones%main".
-- The /comments skill derives the same slug from its own cwd's repo root.
local function queue_path(root)
  local slug = root:gsub("/", "%%")
  return M.config.dir .. "/" .. slug .. ".jsonl"
end

local function read_records(root)
  local fd = io.open(queue_path(root), "r")
  if not fd then return {} end
  local records = {}
  for line in fd:lines() do
    if line ~= "" then
      local ok, rec = pcall(vim.fn.json_decode, line)
      if ok and type(rec) == "table" then
        records[#records + 1] = rec
      end
    end
  end
  fd:close()
  return records
end

local function write_records(root, records)
  local f = io.open(queue_path(root), "w")
  if not f then return false end
  for _, rec in ipairs(records) do
    f:write(vim.fn.json_encode(rec) .. "\n")
  end
  f:close()
  return true
end

-- Append records to a timestamped archive (same dir/scheme the /comments skill
-- uses), so a removal is recoverable.
local function archive_records(root, records)
  local adir = M.config.dir .. "/archive"
  vim.fn.mkdir(adir, "p")
  local slug = root:gsub("/", "%%")
  local path = adir .. "/" .. slug .. "-" .. vim.fn.strftime("%Y%m%dT%H%M%S") .. ".jsonl"
  local f = io.open(path, "a")
  if not f then return end
  for _, rec in ipairs(records) do
    f:write(vim.fn.json_encode(rec) .. "\n")
  end
  f:close()
end

-- Place a dot in the sign column for every queued comment in this buffer.
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local abspath = vim.api.nvim_buf_get_name(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if abspath == "" then return end

  local linecount = vim.api.nvim_buf_line_count(bufnr)
  for _, rec in ipairs(read_records(repo_root_for(abspath))) do
    if rec.path == abspath and type(rec.line) == "number" then
      local lnum = rec.line - 1
      if lnum >= 0 and lnum < linecount then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum, 0, {
          sign_text = M.config.sign,
          sign_hl_group = "CommentsSign",
          priority = M.config.sign_priority,
        })
      end
    end
  end
end

-- Remove every queued comment for the current file (archived first), then redraw.
function M.remove_file()
  local abspath = vim.fn.expand("%:p")
  if abspath == "" then
    notify("current buffer has no file path", vim.log.levels.ERROR)
    return
  end

  local root = repo_root_for(abspath)
  local keep, removed = {}, {}
  for _, rec in ipairs(read_records(root)) do
    if rec.path == abspath then
      removed[#removed + 1] = rec
    else
      keep[#keep + 1] = rec
    end
  end

  if #removed == 0 then
    notify("no comments for " .. vim.fn.expand("%:t"))
    return
  end

  archive_records(root, removed)
  write_records(root, keep)
  M.refresh(0)
  notify(string.format("removed %d comment%s for %s",
    #removed, #removed == 1 and "" or "s", vim.fn.expand("%:t")))
end

local function random_id()
  local charset = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local id = ""
  for _ = 1, 6 do
    local i = math.random(1, #charset)
    id = id .. charset:sub(i, i)
  end
  return id
end

local function send(start_line, end_line, body)
  local abspath = vim.fn.expand("%:p")
  if abspath == "" then
    notify("current buffer has no file path", vim.log.levels.ERROR)
    return
  end

  local root = repo_root_for(abspath)
  local rel = abspath
  if abspath:sub(1, #root + 1) == root .. "/" then
    rel = abspath:sub(#root + 2)
  end

  local record = vim.fn.json_encode({
    id = random_id(),
    path = abspath,
    rel = rel,
    repo = root,
    line = start_line,
    end_line = end_line,
    body = body,
    ts = vim.fn.strftime("%Y-%m-%dT%H:%M:%S"),
  })

  vim.fn.mkdir(M.config.dir, "p")
  local path = queue_path(root)
  local f = io.open(path, "a")
  if not f then
    notify("could not open " .. path, vim.log.levels.ERROR)
    return
  end
  f:write(record .. "\n")
  f:close()

  M.refresh(0)

  local where = vim.fn.expand("%:t") .. ":" .. start_line
  if end_line ~= start_line then
    where = where .. "-" .. end_line
  end
  notify("comment queued (" .. where .. ")")
end

local function prompt(start_line, end_line)
  local sent = false
  vim.ui.input({ prompt = "comment: " }, function(input)
    if input == nil or input == "" or sent then return end
    sent = true
    send(start_line, end_line, input)
  end)
end

function M.comment()
  local l = vim.fn.line(".")
  prompt(l, l)
end

function M.comment_selection()
  local start_line = vim.fn.getpos("'<")[2]
  local end_line = vim.fn.getpos("'>")[2]
  prompt(start_line, end_line)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_set_hl(0, "CommentsSign", { default = true, link = "DiagnosticSignInfo" })

  vim.keymap.set("n", M.config.keys.comment, M.comment,
    { desc = "comments: comment on current line" })

  vim.keymap.set("v", M.config.keys.comment, function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    M.comment_selection()
  end, { desc = "comments: comment on selection" })

  vim.keymap.set("n", M.config.keys.remove, M.remove_file,
    { desc = "comments: remove all comments for current file" })

  -- Re-place dots when a buffer loads or is shown. After the /comments skill
  -- clears the queue, the dots vanish on the next buffer enter (or :CommentsRefresh).
  local group = vim.api.nvim_create_augroup("comments", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
    group = group,
    callback = function(ev) M.refresh(ev.buf) end,
  })

  vim.api.nvim_create_user_command("CommentsRefresh", function() M.refresh(0) end,
    { desc = "comments: re-scan the queue and redraw signs" })
end

return M
