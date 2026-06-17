-- fzf-root.yazi
--
-- Fuzzy-find files/dirs rooted at the directory yazi was launched from ($PWD),
-- regardless of where you've navigated inside the session.
--
-- This mirrors yazi's built-in `fzf` plugin (API as of Yazi 26.x) but swaps the
-- search root: the built-in uses the *current* dir (cx.active.current.cwd); this
-- uses the *launch* dir. $PWD is captured once at process start and yazi never
-- rewrites it, so it always points at where yazi opened.
--
-- fzf walks recursively from its cwd (honoring $FZF_DEFAULT_COMMAND if set), so
-- the picker is scoped to the launch dir's subtree.

local M = {}

-- Grab the multi-selection from the (sync) UI context.
local selected_urls = ya.sync(function()
	local t = {}
	for _, url in pairs(cx.active.selected) do
		t[#t + 1] = url
	end
	return t
end)

function M:entry()
	ya.emit("escape", { visual = true })

	local root = os.getenv("PWD")
	if not root or root == "" then
		return ya.notify { title = "fzf-root", content = "$PWD is unset", timeout = 5, level = "error" }
	end

	local cwd = Url(root)
	local selected = selected_urls()

	local permit = ui.hide() -- release the TUI so fzf can own the terminal
	local output, err = M.run_with(cwd, selected)
	permit:drop()

	if not output then
		return ya.notify { title = "fzf-root", content = tostring(err), timeout = 5, level = "error" }
	end

	local urls = M.split_urls(cwd, output)
	if #urls == 1 then
		local cha = #selected == 0 and fs.cha(urls[1])
		ya.emit(cha and cha.is_dir and "cd" or "reveal", { urls[1], raw = true })
	elseif #urls > 1 then
		urls.state = #selected > 0 and "off" or "on"
		ya.emit("toggle_all", urls)
	end
end

---@param cwd Url
---@param selected Url[]
---@return string?, Error?
function M.run_with(cwd, selected)
	local child, err = Command("fzf")
		:arg("-m")
		:cwd(tostring(cwd))
		:stdin(#selected > 0 and Command.PIPED or Command.INHERIT)
		:stdout(Command.PIPED)
		:spawn()

	if not child then
		return nil, Err("Failed to start `fzf`, error: %s", err)
	end

	for _, u in ipairs(selected) do
		child:write_all(string.format("%s\n", u))
	end
	if #selected > 0 then
		child:flush()
	end

	local output, err = child:wait_with_output()
	if not output then
		return nil, Err("Cannot read `fzf` output, error: %s", err)
	elseif not output.status.success and output.status.code ~= 130 then
		return nil, Err("`fzf` exited with error code %s", output.status.code)
	end
	return output.stdout, nil
end

---@param cwd Url
---@param output string
function M.split_urls(cwd, output)
	local t = {}
	for line in output:gmatch("[^\r\n]+") do
		local u = Url(line)
		t[#t + 1] = u.is_absolute and u or cwd:join(u)
	end
	return t
end

return M
