-- ~/.config/yazi/init.lua (symlinked from dotfiles/yazi/init.lua)

local git = require("git")
git:setup({
	-- Order in the linemode chain; 1500 leaves room for other plugins.
	order = 1500,
})

-- Recolor filenames by git status.
--
-- git.yazi only styles its status *sign* (the "+", "M", "!"); the filename text
-- itself keeps its normal filetype color. We reuse the status git.yazi has
-- already fetched — it stores it on the plugin's module table as `git.dirs` and
-- `git.repos` — and patch a style onto the entry. The lookup mirrors
-- git.yazi's own linemode.
local CODES = { excluded = 99, ignored = 7, untracked = 6 } -- mirror of git.yazi's CODES

local STYLES = {
	[CODES.ignored] = ui.Style():fg("#5c6370"), -- dim gray, recedes
	[CODES.untracked] = ui.Style():fg("#ebd096"), -- soft cream-yellow, reads as new
}

---@return integer? code
local function git_code(file)
	-- Fail safe: if the plugin's internals ever change, just don't restyle.
	if type(git.dirs) ~= "table" then
		return nil
	end

	local url = file.url
	local repo = git.dirs[tostring(url.base or url.parent)]
	if not repo then
		return nil
	elseif repo == CODES.excluded then
		return CODES.ignored -- the entry lives inside an ignored directory
	end

	local statuses = git.repos[repo]
	return statuses and statuses[tostring(url):sub(#repo + 2)] or nil
end

local entity_style = Entity.style
function Entity:style()
	local style = entity_style(self)
	local patch = STYLES[git_code(self._file)]
	return patch and style:patch(patch) or style
end
