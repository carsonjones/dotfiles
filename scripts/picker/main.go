// dotfiles-picker: interactive TUI wrapping scripts/install.sh.
//
// Screen 1: pick a preset (full / slim / minimal / custom).
// Screen 2 (custom only): toggle brew or slim package manager, then check/uncheck
// individual components. Component list mirrors the `want` gates in install.sh
// (keep BREW_COMPONENTS / SLIM_COMPONENTS in sync there).
//
// On confirm: exec ../install.sh with the appropriate flag + INSTALL_ONLY env.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// keep in sync with scripts/install.sh
var brewComponents = []component{
	{"brew", "Homebrew itself (required for any brew formula below)"},
	{"git", "git"},
	{"nvim", "neovim"},
	{"fzf", "fzf"},
	{"ripgrep", "ripgrep (rg)"},
	{"fd", "fd"},
	{"bat", "bat"},
	{"gh", "gh (GitHub CLI)"},
	{"tmux", "tmux"},
	{"zellij", "zellij"},
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

type mode int

const (
	modeFull mode = iota
	modeSlim
	modeMinimal
	modeCustom
)

var modes = []struct {
	m     mode
	label string
	desc  string
}{
	{modeFull, "full", "Homebrew + everything (desktop apps, imagemagick, rust)"},
	{modeSlim, "slim", "Linux apt/curl path, no Homebrew (implies minimal)"},
	{modeMinimal, "minimal", "Homebrew path, skip desktop apps + heavy nvim deps"},
	{modeCustom, "custom", "Pick individual components"},
}

type screen int

const (
	screenMode screen = iota
	screenCustom
)

type model struct {
	screen screen

	// screen 1
	modeCursor int

	// screen 2
	useSlim      bool // false = brew path
	compCursor   int  // 0 = the package-manager toggle row, then 1..N = components
	checked      map[string]bool

	// exit
	quit    bool
	confirm bool

	width  int
}

func initialModel() model {
	return model{
		screen:  screenMode,
		checked: map[string]bool{},
	}
}

func (m model) Init() tea.Cmd { return nil }

func (m *model) currentComponents() []component {
	if m.useSlim {
		return slimComponents
	}
	return brewComponents
}

func (m *model) ensureDefaults() {
	// on first entry to the custom screen, pre-check everything for the chosen path
	if len(m.checked) == 0 {
		for _, c := range m.currentComponents() {
			m.checked[c.name] = true
		}
	}
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
	case tea.KeyMsg:
		k := msg.String()
		if k == "ctrl+c" || k == "q" {
			m.quit = true
			return m, tea.Quit
		}
		switch m.screen {
		case screenMode:
			return m.updateMode(k)
		case screenCustom:
			return m.updateCustom(k)
		}
	}
	return m, nil
}

func (m model) updateMode(k string) (tea.Model, tea.Cmd) {
	switch k {
	case "up", "k":
		if m.modeCursor > 0 {
			m.modeCursor--
		}
	case "down", "j":
		if m.modeCursor < len(modes)-1 {
			m.modeCursor++
		}
	case "enter", " ":
		sel := modes[m.modeCursor].m
		if sel == modeCustom {
			m.screen = screenCustom
			m.compCursor = 1 // land on first component, not the toggle
			m.ensureDefaults()
			return m, nil
		}
		m.confirm = true
		return m, tea.Quit
	}
	return m, nil
}

func (m model) updateCustom(k string) (tea.Model, tea.Cmd) {
	comps := m.currentComponents()
	maxRow := len(comps) // 0 = pkg-mgr toggle, 1..len = components
	switch k {
	case "up", "k":
		if m.compCursor > 0 {
			m.compCursor--
		}
	case "down", "j":
		if m.compCursor < maxRow {
			m.compCursor++
		}
	case "esc", "backspace":
		m.screen = screenMode
	case " ":
		if m.compCursor == 0 {
			m.useSlim = !m.useSlim
			// wipe checks so ensureDefaults repopulates for the new path
			m.checked = map[string]bool{}
			m.ensureDefaults()
		} else {
			c := comps[m.compCursor-1]
			m.checked[c.name] = !m.checked[c.name]
		}
	case "a":
		for _, c := range comps {
			m.checked[c.name] = true
		}
	case "n":
		for _, c := range comps {
			m.checked[c.name] = false
		}
	case "enter":
		m.confirm = true
		return m, tea.Quit
	}
	return m, nil
}

var (
	titleStyle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12"))
	cursorStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("212")).Bold(true)
	helpStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	descStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("244"))
)

func (m model) View() string {
	if m.quit {
		return ""
	}
	switch m.screen {
	case screenMode:
		return m.viewMode()
	case screenCustom:
		return m.viewCustom()
	}
	return ""
}

func (m model) viewMode() string {
	var b strings.Builder
	b.WriteString(titleStyle.Render("dotfiles installer") + "\n\n")
	b.WriteString("Choose a preset:\n\n")
	for i, opt := range modes {
		cursor := "  "
		if i == m.modeCursor {
			cursor = cursorStyle.Render("› ")
		}
		line := fmt.Sprintf("%s%-8s  %s", cursor, opt.label, descStyle.Render(opt.desc))
		b.WriteString(line + "\n")
	}
	b.WriteString("\n")
	b.WriteString(helpStyle.Render("↑/↓ or j/k • enter select • q/ctrl-c quit"))
	return b.String()
}

func (m model) viewCustom() string {
	comps := m.currentComponents()
	var b strings.Builder
	b.WriteString(titleStyle.Render("custom install") + "\n\n")

	// package manager toggle row
	path := "brew (macos/linuxbrew)"
	if m.useSlim {
		path = "slim (linux apt/curl)"
	}
	cursor := "  "
	if m.compCursor == 0 {
		cursor = cursorStyle.Render("› ")
	}
	b.WriteString(fmt.Sprintf("%sPackage manager: [%s]\n\n", cursor, path))

	for i, c := range comps {
		cursor := "  "
		if i+1 == m.compCursor {
			cursor = cursorStyle.Render("› ")
		}
		box := "[ ]"
		if m.checked[c.name] {
			box = "[x]"
		}
		b.WriteString(fmt.Sprintf("%s%s %-12s %s\n", cursor, box, c.name, descStyle.Render(c.desc)))
	}
	b.WriteString("\n")
	b.WriteString(helpStyle.Render("space toggle • a all • n none • enter run • esc back • q quit"))
	return b.String()
}

// resolveInstall returns the absolute path to scripts/install.sh, siblings the
// binary or (in `go run` mode) the source dir.
func resolveInstall() (string, error) {
	exe, err := os.Executable()
	if err == nil {
		// scripts/picker/dotfiles-picker → scripts/install.sh
		candidate := filepath.Join(filepath.Dir(exe), "..", "install.sh")
		if _, err := os.Stat(candidate); err == nil {
			return filepath.Abs(candidate)
		}
	}
	// fallback: relative to cwd (useful during `go run .` from scripts/picker)
	for _, rel := range []string{"../install.sh", "scripts/install.sh", "install.sh"} {
		if _, err := os.Stat(rel); err == nil {
			return filepath.Abs(rel)
		}
	}
	return "", fmt.Errorf("could not locate install.sh")
}

func main() {
	p := tea.NewProgram(initialModel())
	res, err := p.Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, "picker error:", err)
		os.Exit(1)
	}
	m := res.(model)
	if m.quit || !m.confirm {
		os.Exit(130)
	}

	install, err := resolveInstall()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	args := []string{}
	env := os.Environ()

	if m.screen == screenCustom {
		selected := []string{}
		for _, c := range m.currentComponents() {
			if m.checked[c.name] {
				selected = append(selected, c.name)
			}
		}
		if len(selected) == 0 {
			fmt.Fprintln(os.Stderr, "nothing selected; nothing to do")
			os.Exit(0)
		}
		if m.useSlim {
			args = append(args, "--slim")
		}
		env = append(env, "INSTALL_ONLY="+strings.Join(selected, ","))
		fmt.Printf("\n→ %s %s (INSTALL_ONLY=%s)\n\n", install, strings.Join(args, " "), strings.Join(selected, ","))
	} else {
		switch modes[m.modeCursor].m {
		case modeFull:
			// no flag
		case modeSlim:
			args = append(args, "--slim")
		case modeMinimal:
			args = append(args, "--minimal")
		}
		fmt.Printf("\n→ %s %s\n\n", install, strings.Join(args, " "))
	}

	cmd := exec.Command(install, args...)
	cmd.Env = env
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			os.Exit(ee.ExitCode())
		}
		fmt.Fprintln(os.Stderr, "install failed:", err)
		os.Exit(1)
	}
}
