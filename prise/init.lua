local ui = require("prise").tiling()

local function render_minimal_tab_bar(tabs, _, theme)
	local segments = {}
	local divider = "#20252C"

	for i, tab in ipairs(tabs) do
		if i > 1 then
			table.insert(segments, {
				text = " / ",
				style = { fg = divider, bg = theme.bg1 },
			})
		end

		local label = string.format(" %d %s ", tab.index, tab.title)
		local style = {
			fg = tab.is_active and theme.fg_bright or theme.fg_dim,
			bg = tab.is_active and theme.bg2 or theme.bg1,
			bold = tab.is_active,
		}

		table.insert(segments, {
			text = label,
			style = style,
		})
	end

	return segments
end

local function format_tab_title(title)
	return title:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

ui.setup({
	theme = {
		mode_normal = "#61afef",
		mode_command = "#e5c07b",
		bg1 = "#252A34",
		bg2 = "#2C313C",
		bg3 = "#31353f",
		bg4 = "#393f4a",
		fg_bright = "#abb2bf",
		fg_dim = "#5c6370",
		fg_dark = "#181a1f",
		accent = "#61afef",
		green = "#98c379",
		yellow = "#e5c07b",
	},
	borders = {
		enabled = true,
		show_single_pane = false,
		mode = "separator",
		style = "single",
		focused_color = "#4B6B88",
		unfocused_color = "#20252C",
	},
	status_bar = {
		enabled = true,
	},
	tab_bar = {
		show_single_tab = false,
		render = render_minimal_tab_bar,
		format_title = format_tab_title,
	},
	floating = {
		width = 120,
		height = 36,
	},
	leader = "<Space>",
	keybinds = {
		["<D-p>"] = "command_palette",
		["<leader>v"] = "split_horizontal",
		["<leader>s"] = "split_vertical",
		["<leader><Enter>"] = "split_auto",
		["<leader>h"] = "focus_left",
		["<leader>l"] = "focus_right",
		["<leader>j"] = "focus_down",
		["<leader>k"] = "focus_up",
		["<C-h>"] = "focus_left",
		["<C-l>"] = "focus_right",
		["<C-j>"] = "focus_down",
		["<C-k>"] = "focus_up",
		["<leader>w"] = "close_pane",
		["<leader>z"] = "toggle_zoom",
		["<leader>t"] = "new_tab",
		["<leader>c"] = "close_tab",
		["<leader>r"] = "rename_tab",
		["<leader>n"] = "next_tab",
		["<leader>p"] = "previous_tab",
		["<leader><lt>"] = "swap_tab_left",
		["<leader><gt>"] = "swap_tab_right",
		["<leader>d"] = "detach_session",
		["<leader>S"] = "switch_session",
		["<leader>q"] = "quit",
		["<leader>H"] = "resize_left",
		["<leader>L"] = "resize_right",
		["<leader>J"] = "resize_down",
		["<leader>K"] = "resize_up",
		["<leader>1"] = "tab_1",
		["<leader>2"] = "tab_2",
		["<leader>3"] = "tab_3",
		["<leader>4"] = "tab_4",
		["<leader>5"] = "tab_5",
		["<leader>6"] = "tab_6",
		["<leader>7"] = "tab_7",
		["<leader>8"] = "tab_8",
		["<leader>9"] = "tab_9",
		["<leader>0"] = "tab_10",
		["<leader>f"] = "floating_toggle",
		["<leader>+"] = "floating_increase_size",
		["<leader>-"] = "floating_decrease_size",
		["<leader>o"] = "layout_picker",
	},
	macos_option_as_alt = "true",
})

return ui
