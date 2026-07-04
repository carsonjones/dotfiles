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

## maintenance

```sh
scripts/update.sh                     # git pull, relink, refresh brew / mise / bun / uv / nvim / ...
scripts/update.sh --upgrade-plugins   # Lazy! sync (refresh lazy-lock.json) instead of restore
scripts/update.sh --dry-run           # preview

INSTALL_ONLY=zed,ghostty scripts/clean.sh          # uninstall components (mirrors install.sh)
INSTALL_ONLY=fzf,nvim   scripts/clean.sh --slim    # slim-path removers

scripts/nvim-disable.sh --list                     # toggleable nvim plugins
scripts/nvim-disable.sh --disable '3rd/image.nvim' # mutate nvim/lua/local.lua (git-ignored)
```

The picker (`scripts/dotfiles-install`) exposes update / clean / nvim-plugin toggling as top-level actions too.
