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
--   normal mode  <leader>hi  -> inspect/edit queued comments for the current file
--   normal mode  <leader>hx  -> remove all queued comments for the current file
--
-- The inspect pane (<leader>hi) is a floating scratch buffer, one row per queued
-- comment for the current file: "<id>  L<line>[-<end>]  <body>". Edit a body in
-- place, change the L<line> to re-anchor, `dd` a row to delete that comment.
-- Changes reconcile back into the queue when the pane closes (`q` / `<Esc>`).
-- Keep the leading id intact -- it's how a row maps back to its record.
--
-- Lines with a queued comment get a subtle dot in the sign column, refreshed
-- on buffer enter and whenever you add or clear a comment.
--
-- Queue:   ~/.local/share/comments/<repo-slug>.jsonl   (one record per line)
-- Read by: the `/comments` Claude Code skill.
--
-- When nvim runs inside a herdr pane and an idle agent (claude/codex/...) sits
-- in another pane of the same tab, queuing a comment auto-fires the comments
-- skill in that pane -- "/comments" for claude, "$comments" for codex, since the
-- sigil differs per agent (debounced; see `comments.sh dispatch`, which picks it).
-- No herdr / no neighbor / busy agent = silent no-op.

local M = {}

M.config = {
  dir = vim.fn.expand("~/.local/share/comments"),
  keys = {
    comment = "<leader>hc",
    inspect = "<leader>hi",
    remove = "<leader>hx",
  },
  sign = "•",
  -- Above gitsigns (default 6) so the comment dot stays visible on changed
  -- lines. Widen with `signcolumn = "auto:2"` to see both at once.
  sign_priority = 20,
  -- After a comment is queued, auto-fire the comments skill in an idle agent
  -- pane in the same herdr tab (comments.sh dispatch, which picks the right
  -- sigil for that agent). Debounced so a burst of notes fires once; silent
  -- no-op outside herdr or with no idle agent neighbor.
  dispatch = {
    enabled = true,
    debounce_ms = 5000,
    -- clear = ask the receiving agent to archive+clear the addressed comments
    -- when it finishes; false keeps the queue until cleared by hand
    clear = true,
    script = "~/.agents/skills/comments/comments.sh",
  },
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

-- Inspect/edit pane -----------------------------------------------------------
--
-- A floating scratch buffer listing the current file's queued comments, one per
-- row: "<id>  L<line>[-<end>]  <body>". Edit bodies, retarget lines, or `dd` a
-- row to delete. On close the buffer is parsed back into the queue: rows keyed
-- by their leading id update the matching record; missing ids (deleted rows) or
-- rows with an empty body drop the record (archived first).

M._inspect = nil

local function fmt_row(rec)
  local lspec = "L" .. rec.line
  if rec.end_line and rec.end_line ~= rec.line then
    lspec = lspec .. "-" .. rec.end_line
  end
  return string.format("%s  %s  %s", rec.id, lspec, rec.body or "")
end

-- Parse "<id>  L<line>[-<end>]  <body>" -> id, sline, eline, body (body trimmed).
local function parse_row(line)
  local id, lspec, body = line:match("^(%S+)%s+(L%S+)%s+(.*)$")
  if not id then
    id, lspec = line:match("^(%S+)%s+(L%S+)%s*$")
    body = ""
  end
  if not id then return nil end
  local a, b = lspec:match("^L(%d+)%-(%d+)$")
  local s = lspec:match("^L(%d+)$")
  local sline = tonumber(a or s)
  if not sline then return nil end
  local eline = tonumber(b) or sline
  return id, sline, eline, vim.trim(body or "")
end

-- Read the inspect buffer and fold its edits back into the queue on disk.
local function inspect_reconcile(st)
  if not (st.buf and vim.api.nvim_buf_is_valid(st.buf)) then return end
  local lines = vim.api.nvim_buf_get_lines(st.buf, 0, -1, false)

  local by_id = {}
  for _, rec in ipairs(st.records) do by_id[rec.id] = rec end

  local seen, kept = {}, {}
  for _, line in ipairs(lines) do
    if vim.trim(line) ~= "" then
      local id, sline, eline, body = parse_row(line)
      local rec = id and by_id[id]
      if rec and body ~= "" and not seen[id] then
        seen[id] = true
        rec.line = sline
        rec.end_line = eline
        rec.body = body
        kept[#kept + 1] = rec
      end
    end
  end

  -- Records for this file that no longer survive -> archive as deletions.
  local removed = {}
  for _, rec in ipairs(st.records) do
    if not seen[rec.id] then removed[#removed + 1] = rec end
  end

  -- Re-read the queue for other files (may have changed) and reassemble.
  local final = {}
  for _, rec in ipairs(read_records(st.root)) do
    if rec.path ~= st.abspath then final[#final + 1] = rec end
  end
  for _, rec in ipairs(kept) do final[#final + 1] = rec end

  if #removed > 0 then archive_records(st.root, removed) end
  write_records(st.root, final)
end

function M._inspect_finish()
  local st = M._inspect
  if not st then return end
  M._inspect = nil
  pcall(inspect_reconcile, st)
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    vim.api.nvim_win_close(st.win, true)
  end
  M.refresh(0)
end

function M.inspect()
  if M._inspect then M._inspect_finish() end

  local abspath = vim.fn.expand("%:p")
  if abspath == "" then
    notify("current buffer has no file path", vim.log.levels.ERROR)
    return
  end

  local root = repo_root_for(abspath)
  local records = {}
  for _, rec in ipairs(read_records(root)) do
    if rec.path == abspath and type(rec.line) == "number" then
      records[#records + 1] = rec
    end
  end
  if #records == 0 then
    notify("no comments for " .. vim.fn.expand("%:t"))
    return
  end
  table.sort(records, function(a, b) return (a.line or 0) < (b.line or 0) end)

  local lines = {}
  for _, rec in ipairs(records) do lines[#lines + 1] = fmt_row(rec) end

  local uis = vim.api.nvim_list_uis()
  local width = (uis[1] and math.floor(uis[1].width * 0.62)) or 80
  local height = math.max(1, math.min(#lines, 20))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "comments-inspect"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    title = " comments: " .. vim.fn.expand("%:t") .. " (edit · dd to delete) ",
    title_pos = "left",
    row = math.floor((vim.o.lines - height) / 2 - 1),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })

  M._inspect = { win = win, buf = buf, root = root, abspath = abspath, records = records }

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function() M._inspect_finish() end,
      { buffer = buf, nowait = true, desc = "comments: save & close inspect pane" })
  end
  vim.api.nvim_create_autocmd({ "BufWinLeave", "BufLeave" }, {
    buffer = buf,
    once = true,
    callback = function() M._inspect_finish() end,
  })
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

-- Debounced hand-off to comments.sh dispatch. Collects the files touched in a
-- burst of comments; a single file scopes the /comments command to it, several
-- fall back to the whole queue. All herdr/neighbor guards live in the script.
local dispatch_timer
local pending_rels = {}

local function schedule_dispatch(rel)
  local cfg = M.config.dispatch
  if not cfg.enabled or not vim.env.HERDR_PANE_ID then return end
  local script = vim.fn.expand(cfg.script)
  if vim.fn.filereadable(script) ~= 1 then return end

  pending_rels[rel] = true
  dispatch_timer = dispatch_timer or vim.uv.new_timer()
  dispatch_timer:stop()
  dispatch_timer:start(cfg.debounce_ms, 0, vim.schedule_wrap(function()
    local rels = vim.tbl_keys(pending_rels)
    pending_rels = {}
    local args = { "bash", script, "dispatch" }
    if #rels == 1 then args[#args + 1] = rels[1] end
    if cfg.clear then args[#args + 1] = "--clear" end
    vim.system(args, { text = true }, function(out)
      local sent = out.code == 0 and vim.trim(out.stdout or "") or ""
      if sent ~= "" then
        vim.schedule(function() notify("comments dispatched to " .. sent) end)
      end
    end)
  end))
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

  schedule_dispatch(rel)
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

  vim.keymap.set("n", M.config.keys.inspect, M.inspect,
    { desc = "comments: inspect/edit comments for current file" })

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
