package main

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	titleStyle  = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12"))
	cursorStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("212")).Bold(true)
	helpStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	descStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("244"))
	warnStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
)

// ---------------- menu screen ----------------

func (m model) updateMenu(k string) (tea.Model, tea.Cmd) {
	switch k {
	case "q":
		m.quit = true
		return m, tea.Quit
	case "up", "k":
		if m.menuCursor > 0 {
			m.menuCursor--
		}
	case "down", "j":
		if m.menuCursor < len(menu)-1 {
			m.menuCursor++
		}
	case "enter", " ":
		sel := menu[m.menuCursor].m
		switch sel {
		case modeQuit:
			m.quit = true
			return m, tea.Quit
		case modeCustom:
			m.screen = screenCustom
			m.compCursor = 1
			m.ensureInstallDefaults()
			return m, nil
		case modeUpdate:
			m.screen = screenUpdate
			return m, nil
		case modeClean:
			m.screen = screenClean
			m.compCursor = 1
			m.ensureCleanDefaults()
			return m, nil
		case modeNvim:
			m.screen = screenNvim
			plugins, err := scanNvimPlugins()
			if err != nil {
				m.nvimErr = err.Error()
			}
			m.nvimPlugins = plugins
			m.nvimCursor = 0
			return m, nil
		default:
			m.action = actionInstallPreset
			m.preset = sel
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) viewMenu() string {
	var b strings.Builder
	b.WriteString(titleStyle.Render("dotfiles") + "\n\n")
	b.WriteString("Choose an action:\n\n")
	for i, it := range menu {
		if it.sep {
			b.WriteString("\n")
		}
		cursor := "  "
		if i == m.menuCursor {
			cursor = cursorStyle.Render("› ")
		}
		desc := ""
		if it.desc != "" {
			desc = descStyle.Render(it.desc)
		}
		b.WriteString(fmt.Sprintf("%s%-13s  %s\n", cursor, it.label, desc))
	}
	b.WriteString("\n")
	b.WriteString(helpStyle.Render("↑/↓ or j/k • enter select • q/ctrl-c quit"))
	return b.String()
}

// ---------------- custom (install) screen ----------------

func (m *model) currentComponents() []component {
	if m.useSlim {
		return slimComponents
	}
	return brewComponents
}

func (m *model) ensureInstallDefaults() {
	if len(m.installChecks) == 0 {
		for _, c := range m.currentComponents() {
			m.installChecks[c.name] = true
		}
	}
}

func (m model) updateCustom(k string) (tea.Model, tea.Cmd) {
	comps := m.currentComponents()
	maxRow := len(comps)
	switch k {
	case "q":
		m.quit = true
		return m, tea.Quit
	case "up", "k":
		if m.compCursor > 0 {
			m.compCursor--
		}
	case "down", "j":
		if m.compCursor < maxRow {
			m.compCursor++
		}
	case "esc", "backspace":
		m.screen = screenMenu
	case " ":
		if m.compCursor == 0 {
			m.useSlim = !m.useSlim
			m.installChecks = map[string]bool{}
			m.ensureInstallDefaults()
		} else {
			c := comps[m.compCursor-1]
			m.installChecks[c.name] = !m.installChecks[c.name]
		}
	case "a":
		for _, c := range comps {
			m.installChecks[c.name] = true
		}
	case "n":
		for _, c := range comps {
			m.installChecks[c.name] = false
		}
	case "enter":
		m.action = actionInstallCustom
		return m, tea.Quit
	}
	return m, nil
}

func (m model) viewCustom() string {
	return m.viewCheckboxScreen("custom install", m.installChecks, nil)
}

// ---------------- clean screen ----------------

func (m *model) ensureCleanDefaults() {
	if len(m.cleanChecks) == 0 {
		// probe each component: default-check only ones that look installed.
		for _, c := range m.currentComponents() {
			m.cleanChecks[c.name] = isProbablyInstalled(c.name)
		}
	}
}

func (m model) updateClean(k string) (tea.Model, tea.Cmd) {
	comps := m.currentComponents()
	maxRow := len(comps)
	switch k {
	case "q":
		m.quit = true
		return m, tea.Quit
	case "up", "k":
		if m.compCursor > 0 {
			m.compCursor--
		}
	case "down", "j":
		if m.compCursor < maxRow {
			m.compCursor++
		}
	case "esc", "backspace":
		m.screen = screenMenu
	case " ":
		if m.compCursor == 0 {
			m.useSlim = !m.useSlim
			m.cleanChecks = map[string]bool{}
			m.ensureCleanDefaults()
		} else {
			c := comps[m.compCursor-1]
			m.cleanChecks[c.name] = !m.cleanChecks[c.name]
		}
	case "a":
		for _, c := range comps {
			m.cleanChecks[c.name] = true
		}
	case "n":
		for _, c := range comps {
			m.cleanChecks[c.name] = false
		}
	case "enter":
		m.action = actionClean
		return m, tea.Quit
	}
	return m, nil
}

func (m model) viewClean() string {
	hint := warnStyle.Render("guardrails: zsh (if it's your $SHELL) and brew (if formulas remain) refuse to remove without --force*")
	return m.viewCheckboxScreen("clean (uninstall)", m.cleanChecks, []string{hint})
}

func (m model) viewCheckboxScreen(title string, checked map[string]bool, extras []string) string {
	comps := m.currentComponents()
	var b strings.Builder
	b.WriteString(titleStyle.Render(title) + "\n\n")

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
		if checked[c.name] {
			box = "[x]"
		}
		b.WriteString(fmt.Sprintf("%s%s %-12s %s\n", cursor, box, c.name, descStyle.Render(c.desc)))
	}
	b.WriteString("\n")
	for _, e := range extras {
		b.WriteString(e + "\n")
	}
	b.WriteString(helpStyle.Render("space toggle • a all • n none • enter run • esc back • q quit"))
	return b.String()
}

// ---------------- update screen ----------------

func (m model) updateUpdate(k string) (tea.Model, tea.Cmd) {
	switch k {
	case "q":
		m.quit = true
		return m, tea.Quit
	case "esc", "backspace":
		m.screen = screenMenu
	case " ":
		m.upgradePlugins = !m.upgradePlugins
	case "enter":
		m.action = actionUpdate
		return m, tea.Quit
	}
	return m, nil
}

func (m model) viewUpdate() string {
	var b strings.Builder
	b.WriteString(titleStyle.Render("update") + "\n\n")
	b.WriteString(descStyle.Render("Runs scripts/update.sh: git pull, link, refresh package managers,") + "\n")
	b.WriteString(descStyle.Render("language toolchains, and plugin ecosystems.") + "\n\n")

	box := "[ ]"
	if m.upgradePlugins {
		box = "[x]"
	}
	b.WriteString(fmt.Sprintf("  %s upgrade plugins (Lazy! sync + refresh lazy-lock.json)\n", box))
	b.WriteString("     " + descStyle.Render("default is Lazy! restore, which respects the committed lock") + "\n\n")

	b.WriteString(helpStyle.Render("space toggle • enter run • esc back • q quit"))
	return b.String()
}

// ---------------- nvim screen ----------------

func (m model) updateNvim(k string) (tea.Model, tea.Cmd) {
	switch k {
	case "q":
		m.quit = true
		return m, tea.Quit
	case "esc", "backspace", "enter":
		m.screen = screenMenu
		return m, nil
	case "up", "k":
		if m.nvimCursor > 0 {
			m.nvimCursor--
		}
	case "down", "j":
		if m.nvimCursor < len(m.nvimPlugins)-1 {
			m.nvimCursor++
		}
	case " ":
		if len(m.nvimPlugins) == 0 {
			return m, nil
		}
		p := m.nvimPlugins[m.nvimCursor]
		if err := toggleNvimPlugin(p.key, !p.disabled); err != nil {
			m.nvimErr = err.Error()
			return m, nil
		}
		m.nvimPlugins[m.nvimCursor].disabled = !p.disabled
		m.nvimErr = ""
	}
	return m, nil
}

func (m model) viewNvim() string {
	var b strings.Builder
	b.WriteString(titleStyle.Render("nvim plugins") + "\n\n")
	b.WriteString(descStyle.Render("Toggle machine-local plugin disables (nvim/lua/local.lua, git-ignored).") + "\n\n")

	if m.nvimErr != "" {
		b.WriteString(warnStyle.Render("error: "+m.nvimErr) + "\n\n")
	}
	if len(m.nvimPlugins) == 0 {
		b.WriteString("  (no toggleable plugins found)\n\n")
	}
	for i, p := range m.nvimPlugins {
		cursor := "  "
		if i == m.nvimCursor {
			cursor = cursorStyle.Render("› ")
		}
		box := "[ ]"
		state := "enabled"
		if p.disabled {
			box = "[x]"
			state = "disabled"
		}
		b.WriteString(fmt.Sprintf("%s%s %-32s %s\n", cursor, box, p.key, descStyle.Render(state+"  ("+p.source+")")))
	}
	b.WriteString("\n")
	b.WriteString(helpStyle.Render("space toggle (applies immediately) • esc/enter back • q quit"))
	return b.String()
}
