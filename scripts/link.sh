#!/bin/bash
# Symlink dotfiles configs into place. Idempotent — safe to re-run any time to
# refresh a machine after `git pull`. Installs NO tools (see install.sh for that).
#
#   scripts/link.sh                 # link everything
#   scripts/link.sh --minimal       # skip desktop-only configs (ghostty/zed), trim nvim
#   scripts/link.sh nvim claude     # link only the named components
#   scripts/link.sh -m yazi         # minimal + only yazi
#
# Components: zsh nvim ghostty zed zellij herdr comview tmux yazi claude pi codex
set -e

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -n "$DOTFILES" ] || { echo "error: DOTFILES unset, refusing to link" >&2; exit 1; }

MINIMAL=${MINIMAL:-false}
COMPONENTS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --minimal|-m) MINIMAL=true ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *)  COMPONENTS+=("$1") ;;
    esac
    shift
done

if [[ "$OSTYPE" == "darwin"* ]]; then OS="macos"; else OS="linux"; fi

link_zsh() {
    echo "Linking zsh configs..."
    ln -sf "$DOTFILES/zsh/zshrc" ~/.zshrc
    ln -sf "$DOTFILES/zsh/zshenv" ~/.zshenv
    ln -sf "$DOTFILES/zsh/p10k.zsh" ~/.p10k.zsh
    if [ ! -f ~/.zshrc.local ]; then
        cp "$DOTFILES/zsh/zshrc.local.template" ~/.zshrc.local
        echo "Created ~/.zshrc.local - fill in your secrets"
    fi
}

link_nvim() {
    echo "Linking nvim config..."
    mkdir -p ~/.config
    rm -rf ~/.config/nvim
    ln -sf "$DOTFILES/nvim" ~/.config/nvim

    # Write minimal local.lua to disable heavy plugins
    mkdir -p "$DOTFILES/nvim/lua"
    if $MINIMAL; then
        cat > "$DOTFILES/nvim/lua/local.lua" <<'EOF'
-- minimal mode: disable heavy plugins
vim.g.local_disabled_plugins = { ['3rd/image.nvim'] = true }
EOF
        echo "Wrote minimal nvim local.lua (image.nvim disabled)"
    elif [ ! -f "$DOTFILES/nvim/lua/local.lua" ]; then
        touch "$DOTFILES/nvim/lua/local.lua"
    fi
}

link_ghostty() {
    echo "Linking ghostty config..."
    if [[ "$OS" == "macos" ]]; then
        mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"
        ln -sf "$DOTFILES/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
    else
        mkdir -p ~/.config/ghostty
        ln -sf "$DOTFILES/ghostty/config" ~/.config/ghostty/config
    fi
}

link_zed() {
    echo "Linking zed config..."
    mkdir -p ~/.config/zed
    ln -sf "$DOTFILES/zed/settings.json" ~/.config/zed/settings.json
    ln -sf "$DOTFILES/zed/keymap.json" ~/.config/zed/keymap.json
}

link_zellij() {
    echo "Linking zellij config..."
    mkdir -p ~/.config/zellij
    ln -sf "$DOTFILES/zellij/config.kdl" ~/.config/zellij/config.kdl
    ln -sfn "$DOTFILES/zellij/layouts" ~/.config/zellij/layouts
}

link_herdr() {
    echo "Linking herdr config..."
    mkdir -p ~/.config/herdr
    ln -sfn "$DOTFILES/herdr/config.toml" ~/.config/herdr/config.toml
}

link_comview() {
    echo "Linking comview config..."
    mkdir -p ~/.config/comview
    ln -sf "$DOTFILES/comview/config.json" ~/.config/comview/config.json
}

link_tmux() {
    echo "Linking tmux config..."
    mkdir -p ~/.config/tmux
    ln -sf "$DOTFILES/tmux/tmux.conf" ~/.config/tmux/tmux.conf
    # TPM (tmux plugin manager) — config references it, clone if missing
    if command -v tmux &>/dev/null && [ ! -d ~/.config/tmux/plugins/tpm ]; then
        echo "Installing TPM..."
        git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
    fi
}

link_yazi() {
    echo "Linking yazi config..."
    mkdir -p ~/.config/yazi
    ln -sf "$DOTFILES/yazi/yazi.toml" ~/.config/yazi/yazi.toml
    ln -sf "$DOTFILES/yazi/theme.toml" ~/.config/yazi/theme.toml
    ln -sf "$DOTFILES/yazi/keymap.toml" ~/.config/yazi/keymap.toml
    ln -sf "$DOTFILES/yazi/init.lua" ~/.config/yazi/init.lua
    ln -sf "$DOTFILES/yazi/package.toml" ~/.config/yazi/package.toml
    if command -v ya >/dev/null 2>&1; then
        # Fetch declared deps (e.g. git.yazi) into ~/.config/yazi/plugins/
        ya pkg install >/dev/null 2>&1 || true
    fi
    # Link local (in-repo) yazi plugins, e.g. fzf-root.yazi used by the <C-p> keymap.
    # `ya pkg install` only handles remote deps, so these must be linked by hand.
    if [ -d "$DOTFILES/yazi/plugins" ]; then
        mkdir -p ~/.config/yazi/plugins
        for plugin in "$DOTFILES"/yazi/plugins/*/; do
            [ -d "$plugin" ] && ln -sfn "${plugin%/}" "$HOME/.config/yazi/plugins/$(basename "$plugin")"
        done
    fi
}

link_claude() {
    echo "Linking claude config..."
    mkdir -p ~/.claude
    ln -sf "$DOTFILES/claude/settings.json" ~/.claude/settings.json
    ln -sf "$DOTFILES/claude/CLAUDE.md" ~/.claude/CLAUDE.md
    ln -sf "$DOTFILES/claude/mcp_settings.json" ~/.claude/mcp_settings.json
    # Skills per-item (leaves other skills in ~/.claude/skills untouched)
    if [ -d "$DOTFILES/claude/skills" ]; then
        mkdir -p ~/.claude/skills
        for item in "$DOTFILES"/claude/skills/*; do
            [ -e "$item" ] && ln -sfn "$item" "$HOME/.claude/skills/$(basename "$item")"
        done
    fi
}

link_pi() {
    # Link pi config/resources (do not link auth.json, sessions, or bin)
    echo "Linking pi config..."
    mkdir -p ~/.pi/agent
    if [ -f "$DOTFILES/pi/settings.json" ]; then
        ln -sf "$DOTFILES/pi/settings.json" ~/.pi/agent/settings.json
    fi
    for kind in extensions prompts skills themes; do
        if [ -d "$DOTFILES/pi/$kind" ]; then
            mkdir -p "$HOME/.pi/agent/$kind"
            for item in "$DOTFILES"/pi/"$kind"/*; do
                [ -e "$item" ] && ln -sfn "$item" "$HOME/.pi/agent/$kind/$(basename "$item")"
            done
        fi
    done
    # Vibes are generated data; link the whole dir when safe so `/vibe generate` is tracked.
    if [ -d "$DOTFILES/pi/vibes" ]; then
        if [ ! -e "$HOME/.pi/agent/vibes" ] || [ -L "$HOME/.pi/agent/vibes" ]; then
            ln -sfn "$DOTFILES/pi/vibes" "$HOME/.pi/agent/vibes"
        else
            for item in "$DOTFILES"/pi/vibes/*; do
                [ -e "$item" ] && ln -sfn "$item" "$HOME/.pi/agent/vibes/$(basename "$item")"
            done
        fi
    fi
}

link_codex() {
    echo "Linking codex config..."
    ln -sfn "$DOTFILES/.codex" ~/.codex
}

link_all() {
    link_zsh
    link_nvim
    if ! $MINIMAL; then
        link_ghostty
        link_zed
    fi
    link_zellij
    link_herdr
    link_comview
    link_tmux
    link_yazi
    link_claude
    link_pi
    link_codex
}

if [ ${#COMPONENTS[@]} -eq 0 ]; then
    link_all
else
    for c in "${COMPONENTS[@]}"; do
        if ! declare -F "link_$c" >/dev/null; then
            echo "Unknown component: $c" >&2
            exit 1
        fi
        "link_$c"
    done
fi
