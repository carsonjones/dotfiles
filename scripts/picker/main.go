// dotfiles-picker: interactive TUI wrapping scripts/{install,update,clean,nvim-disable}.sh.
//
// Screen 1 (menu): install presets (full/slim/minimal/custom) + top-level
// actions (update / clean / nvim plugins / quit).
// Subscreens:
//   custom  — pick brew/slim + individual components, exec install.sh
//   update  — confirm + toggle --upgrade-plugins, exec update.sh
//   clean   — pick brew/slim + individual components, exec clean.sh
//   nvim    — toggle machine-local plugin disables via nvim-disable.sh
//
// Component lists mirror the `want` gates in install.sh — keep BREW_COMPONENTS
// / SLIM_COMPONENTS in sync there.
package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

type screen int

const (
	screenMenu screen = iota
	screenCustom
	screenUpdate
	screenClean
	screenNvim
)

// action is the outcome the model wants main() to execute after tea.Quit.
type action int

const (
	actionNone action = iota
	actionInstallPreset
	actionInstallCustom
	actionUpdate
	actionClean
)

type model struct {
	screen screen

	// screen 1
	menuCursor int

	// custom / clean shared shape
	useSlim       bool
	compCursor    int
	installChecks map[string]bool
	cleanChecks   map[string]bool

	// update
	upgradePlugins bool

	// nvim
	nvimPlugins []nvimPlugin
	nvimCursor  int
	nvimErr     string

	// exit
	quit     bool
	action   action
	preset   modeKind
}

func initialModel() model {
	return model{
		screen:        screenMenu,
		installChecks: map[string]bool{},
		cleanChecks:   map[string]bool{},
	}
}

func (m model) Init() tea.Cmd { return nil }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		k := msg.String()
		if k == "ctrl+c" {
			m.quit = true
			return m, tea.Quit
		}
		switch m.screen {
		case screenMenu:
			return m.updateMenu(k)
		case screenCustom:
			return m.updateCustom(k)
		case screenUpdate:
			return m.updateUpdate(k)
		case screenClean:
			return m.updateClean(k)
		case screenNvim:
			return m.updateNvim(k)
		}
	}
	return m, nil
}

func (m model) View() string {
	if m.quit {
		return ""
	}
	switch m.screen {
	case screenMenu:
		return m.viewMenu()
	case screenCustom:
		return m.viewCustom()
	case screenUpdate:
		return m.viewUpdate()
	case screenClean:
		return m.viewClean()
	case screenNvim:
		return m.viewNvim()
	}
	return ""
}

func main() {
	p := tea.NewProgram(initialModel())
	res, err := p.Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, "picker error:", err)
		os.Exit(1)
	}
	m := res.(model)
	if m.quit || m.action == actionNone {
		os.Exit(130)
	}
	if err := m.exec(); err != nil {
		if code, ok := exitCodeFrom(err); ok {
			os.Exit(code)
		}
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
