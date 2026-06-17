-- ~/.config/yazi/init.lua (symlinked from dotfiles/yazi/init.lua)

local git = require("git")
git:setup({
	-- Order in the linemode chain; 1500 leaves room for other plugins.
	order = 1500,
})

-- Dim git-ignored files and directories.
--
-- git.yazi only recolors its status *sign* (the gray "!"); the filename text
-- itself keeps its normal filetype color. We reuse the status git.yazi has
-- already fetched — it stores it on the plugin's module table as `git.dirs`
-- and `git.repos` — and, for anything it classifies as ignored, patch a dim
-- gray onto the entry's style. The lookup mirrors git.yazi's own linemode.
local IGNORED, EXCLUDED = 6, 99 -- mirror of git.yazi's CODES.ignored / .excluded
local DIM = ui.Style():fg("#5c6370") -- onedark comment gray (matches theme.toml)

local function is_ignored(file)
	-- Fail safe: if the plugin's internals ever change, just don't dim anything.
	if type(git.dirs) ~= "table" then
		return false
	end

	local url = file.url
	local repo = git.dirs[tostring(url.base or url.parent)]
	if not repo then
		return false
	elseif repo == EXCLUDED then
		return true -- the entry lives inside an ignored directory
	end

	local statuses = git.repos[repo]
	return statuses ~= nil and statuses[tostring(url):sub(#repo + 2)] == IGNORED
end

local entity_style = Entity.style
function Entity:style()
	local style = entity_style(self)
	if is_ignored(self._file) then
		return style:patch(DIM)
	end
	return style
end
