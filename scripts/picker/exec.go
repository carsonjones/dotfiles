package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// resolveScript locates a sibling shell script (install.sh, update.sh, ...).
func resolveScript(name string) (string, error) {
	exe, err := os.Executable()
	if err == nil {
		candidate := filepath.Join(filepath.Dir(exe), "..", name)
		if _, err := os.Stat(candidate); err == nil {
			return filepath.Abs(candidate)
		}
	}
	for _, rel := range []string{"../" + name, "scripts/" + name, name} {
		if _, err := os.Stat(rel); err == nil {
			return filepath.Abs(rel)
		}
	}
	return "", fmt.Errorf("could not locate %s", name)
}

func runScript(script string, args []string, extraEnv []string) error {
	cmd := exec.Command(script, args...)
	cmd.Env = append(os.Environ(), extraEnv...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	fmt.Printf("\n→ %s %s\n\n", script, strings.Join(args, " "))
	return cmd.Run()
}

func exitCodeFrom(err error) (int, bool) {
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return ee.ExitCode(), true
	}
	return 0, false
}

func (m model) exec() error {
	switch m.action {
	case actionInstallPreset:
		script, err := resolveScript("install.sh")
		if err != nil {
			return err
		}
		args := []string{}
		switch m.preset {
		case modeSlim:
			args = append(args, "--slim")
		case modeMinimal:
			args = append(args, "--minimal")
		}
		return runScript(script, args, nil)

	case actionInstallCustom:
		return execWithComponents("install.sh", m.installChecks, m.useSlim, nil)

	case actionUpdate:
		script, err := resolveScript("update.sh")
		if err != nil {
			return err
		}
		args := []string{}
		if m.upgradePlugins {
			args = append(args, "--upgrade-plugins")
		}
		return runScript(script, args, nil)

	case actionClean:
		return execWithComponents("clean.sh", m.cleanChecks, m.useSlim, []string{"--yes"})
	}
	return nil
}

func execWithComponents(scriptName string, checked map[string]bool, useSlim bool, extraArgs []string) error {
	script, err := resolveScript(scriptName)
	if err != nil {
		return err
	}
	comps := brewComponents
	if useSlim {
		comps = slimComponents
	}
	selected := []string{}
	for _, c := range comps {
		if checked[c.name] {
			selected = append(selected, c.name)
		}
	}
	if len(selected) == 0 {
		fmt.Fprintln(os.Stderr, "nothing selected; nothing to do")
		return nil
	}
	args := append([]string{}, extraArgs...)
	if useSlim {
		args = append(args, "--slim")
	}
	env := []string{"INSTALL_ONLY=" + strings.Join(selected, ",")}
	return runScript(script, args, env)
}

// isProbablyInstalled: cheap best-effort check used to pre-populate clean-screen
// defaults. Not exhaustive — false positives/negatives are OK, the user checks
// the final set before hitting enter.
func isProbablyInstalled(comp string) bool {
	// map component -> binary name to probe with `command -v`
	bin := map[string]string{
		"git": "git", "nvim": "nvim", "fzf": "fzf", "ripgrep": "rg", "fd": "fd",
		"bat": "bat", "gh": "gh", "zsh": "zsh",
		"lazygit": "lazygit", "sqlite3": "sqlite3", "yazi": "yazi", "hunk": "hunk",
		"imagemagick": "magick", "docker": "docker", "zed": "zed",
		"ghostty": "ghostty", "tailscale": "tailscale", "rust": "rustup",
		"mise": "mise", "bun": "bun", "uv": "uv", "brew": "brew", "herdr": "herdr",
	}
	if b, ok := bin[comp]; ok {
		if _, err := exec.LookPath(b); err == nil {
			return true
		}
		return false
	}
	// Non-binary components — probe by known filesystem markers.
	home, _ := os.UserHomeDir()
	switch comp {
	case "zinit":
		_, err := os.Stat(filepath.Join(home, ".local", "share", "zinit", "zinit.git"))
		return err == nil
	case "node":
		if _, err := exec.LookPath("node"); err == nil {
			return true
		}
		_, err := os.Stat(filepath.Join(home, ".local", "share", "mise", "installs", "node"))
		return err == nil
	case "link", "apt-core":
		// always default-on: user is here to clean, they probably want these.
		return true
	}
	return false
}

// ---------------- nvim plugin scan/toggle ----------------

type nvimPlugin struct {
	key      string
	source   string
	disabled bool
}

func scanNvimPlugins() ([]nvimPlugin, error) {
	script, err := resolveScript("nvim-disable.sh")
	if err != nil {
		return nil, err
	}
	out, err := exec.Command(script, "--list").Output()
	if err != nil {
		return nil, err
	}
	var plugins []nvimPlugin
	s := bufio.NewScanner(strings.NewReader(string(out)))
	for s.Scan() {
		line := s.Text()
		parts := strings.SplitN(line, "\t", 3)
		if len(parts) < 3 {
			continue
		}
		plugins = append(plugins, nvimPlugin{
			key:      parts[0],
			disabled: parts[1] == "disabled",
			source:   parts[2],
		})
	}
	return plugins, nil
}

func toggleNvimPlugin(key string, disable bool) error {
	script, err := resolveScript("nvim-disable.sh")
	if err != nil {
		return err
	}
	flag := "--enable"
	if disable {
		flag = "--disable"
	}
	cmd := exec.Command(script, flag, key)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%s %s: %s", flag, key, strings.TrimSpace(string(out)))
	}
	return nil
}
