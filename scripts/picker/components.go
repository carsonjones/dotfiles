package main

// keep in sync with scripts/install.sh and scripts/clean.sh
var brewComponents = []component{
	{"brew", "Homebrew itself (required for any brew formula below)"},
	{"git", "git"},
	{"nvim", "neovim"},
	{"fzf", "fzf"},
	{"ripgrep", "ripgrep (rg)"},
	{"fd", "fd"},
	{"bat", "bat"},
	{"gh", "gh (GitHub CLI)"},
	{"zsh", "zsh (and set as default shell)"},
	{"lazygit", "lazygit"},
	{"sqlite3", "sqlite"},
	{"yazi", "yazi + ya"},
	{"hunk", "hunk (terminal diff viewer)"},
	{"imagemagick", "imagemagick (image.nvim dep)"},
	{"docker", "Docker"},
	{"zed", "Zed editor"},
	{"ghostty", "Ghostty terminal"},
	{"tailscale", "Tailscale"},
	{"rust", "Rust toolchain (rustup)"},
	{"mise", "mise version manager"},
	{"bun", "bun"},
	{"uv", "uv (python)"},
	{"zinit", "zinit (zsh plugin manager)"},
	{"node", "Node.js LTS via mise"},
	{"link", "symlink dotfile configs (scripts/link.sh)"},
	{"herdr-plugins", "herdr external plugins (picker-plus, herdr-plus, command-palette, agent-dashboard)"},
}

var slimComponents = []component{
	{"apt-core", "apt: git, fd, bat, ripgrep, unzip, curl"},
	{"gh", "gh (GitHub CLI, apt repo)"},
	{"fzf", "fzf (release binary, needed for `fzf --zsh`)"},
	{"nvim", "neovim (release tarball)"},
	{"yazi", "yazi (release zip)"},
	{"hunk", "hunk (release tarball)"},
	{"herdr", "herdr"},
	{"bun", "bun"},
	{"uv", "uv (python)"},
	{"mise", "mise version manager"},
	{"zinit", "zinit (zsh plugin manager)"},
	{"node", "Node.js LTS via mise"},
	{"link", "symlink dotfile configs (scripts/link.sh)"},
}

type component struct {
	name string
	desc string
}

type modeKind int

const (
	modeFull modeKind = iota
	modeSlim
	modeMinimal
	modeCustom
	// non-install top-level actions
	modeUpdate
	modeClean
	modeNvim
	modeQuit
)

type menuItem struct {
	m     modeKind
	label string
	desc  string
	sep   bool // draws a separator line above this item
}

var menu = []menuItem{
	{m: modeFull, label: "full", desc: "Homebrew + everything (desktop apps, imagemagick, rust)"},
	{m: modeSlim, label: "slim", desc: "Linux apt/curl path, no Homebrew (implies minimal)"},
	{m: modeMinimal, label: "minimal", desc: "Homebrew path, skip desktop apps + heavy nvim deps"},
	{m: modeCustom, label: "custom", desc: "Pick individual components"},
	{m: modeUpdate, label: "update", desc: "Refresh managers, plugins, symlinks (scripts/update.sh)", sep: true},
	{m: modeClean, label: "clean", desc: "Uninstall selected components (scripts/clean.sh)"},
	{m: modeNvim, label: "nvim plugins", desc: "Toggle machine-local plugin disables"},
	{m: modeQuit, label: "quit", desc: "", sep: true},
}
