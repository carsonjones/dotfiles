-- ~/.config/yazi/init.lua (symlinked from dotfiles/yazi/init.lua)

require("git"):setup({
	-- Order in the linemode chain; 1500 leaves room for other plugins.
	order = 1500,
})
