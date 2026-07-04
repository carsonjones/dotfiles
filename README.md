```
zsh/          # zsh config (zinit + p10k)
nvim/         # neovim config (kickstart-based)
zed/          # zed editor config
ghostty/      # ghostty terminal config
claude/       # claude code settings
cursor/       # cursor mcp template
scripts/      # install script + picker TUI
```

## install

```sh
# interactive picker (Go + bubbletea, built on first run)
scripts/dotfiles-install

# non-interactive (skips the TUI, forwards to install.sh)
scripts/dotfiles-install --full            # brew + everything
scripts/dotfiles-install --minimal         # brew, no desktop apps
scripts/dotfiles-install --slim            # linux apt/curl path
scripts/install.sh --list-components       # what the picker toggles

# custom install: skip the TUI and pass INSTALL_ONLY directly
INSTALL_ONLY=brew-core,mise,link scripts/install.sh
```

Symlink refresh only (no tool installs): `scripts/link.sh` (`--minimal` optional).
