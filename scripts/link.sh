#!/bin/bash
# Symlink dotfiles configs into place. Idempotent — safe to re-run any time to
# refresh a machine after `git pull`. Installs NO tools (see install.sh for that).
#
#   scripts/link.sh                 # link everything
#   scripts/link.sh --minimal       # skip desktop-only configs (ghostty/zed), trim nvim
#   scripts/link.sh nvim claude     # link only the named components
#   scripts/link.sh -m yazi         # minimal + only yazi
#   scripts/link.sh --unlink        # remove symlinks that point at $DOTFILES/*
#   scripts/link.sh --unlink nvim   # unlink only the named components
#
# Components: zsh nvim ghostty zed zellij herdr comview tmux yazi agents claude pi codex
set -e

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -n "$DOTFILES" ] || { echo "error: DOTFILES unset, refusing to link" >&2; exit 1; }

MINIMAL=${MINIMAL:-false}
UNLINK=false
COMPONENTS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --minimal|-m) MINIMAL=true ;;
        --unlink)     UNLINK=true ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
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
    ln -sfn "$DOTFILES/herdr/plugins" ~/.config/herdr/plugins
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

link_agent_skills() {
    # Shared Agent Skills used by multiple harnesses. Link per-item so real
    # local/user skill files and directories in the destination stay untouched.
    local dest="$1" item target
    [ -d "$DOTFILES/agents/skills" ] || return 0
    mkdir -p "$dest"
    for item in "$DOTFILES"/agents/skills/*; do
        [ -e "$item" ] || continue
        target="$dest/$(basename "$item")"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
            echo "  warning: leaving existing agent skill untouched: $target" >&2
            continue
        fi
        ln -sfn "$item" "$target"
    done
}

link_agents() {
    echo "Linking shared agent skills..."
    link_agent_skills "$HOME/.agents/skills"
}

link_claude() {
    echo "Linking claude config..."
    mkdir -p ~/.claude
    # settings.json is generated: portable base deep-merged with an optional
    # per-machine overlay (claude/settings.local.json, gitignored). Machine-specific
    local base="$DOTFILES/claude/settings.json" local_overlay="$DOTFILES/claude/settings.local.json"
    rm -f ~/.claude/settings.json   # clear stale target before regenerating
    if [ -f "$local_overlay" ] && command -v jq >/dev/null 2>&1; then
        jq -s '.[0] * .[1]' "$base" "$local_overlay" > ~/.claude/settings.json
    else
        [ -f "$local_overlay" ] && echo "  warning: jq missing, per-machine claude overlay not merged"
        cp "$base" ~/.claude/settings.json
    fi
    ln -sf "$DOTFILES/claude/CLAUDE.md" ~/.claude/CLAUDE.md
    ln -sf "$DOTFILES/claude/mcp_settings.json" ~/.claude/mcp_settings.json
    link_agent_skills "$HOME/.agents/skills"
    link_agent_skills "$HOME/.claude/skills"
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
    link_agent_skills "$HOME/.agents/skills"
    link_agent_skills "$HOME/.pi/agent/skills"
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
    link_agent_skills "$HOME/.agents/skills"
    link_agent_skills "$HOME/.codex/skills"
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
    link_agents
    link_claude
    link_pi
    link_codex
}

# --- unlink ----------------------------------------------------------------
# Best-effort removal of symlinks this script would have created. Only unlinks
# a path if it's a symlink pointing into $DOTFILES/* — user-edited files (e.g.
# ~/.zshrc.local), the TPM clone, and per-machine data are left alone.
rm_dot_symlink() {
    local path="$1"
    if [ -L "$path" ]; then
        local target
        target="$(readlink "$path")"
        case "$target" in
            "$DOTFILES"/*|"$DOTFILES")
                echo "  unlink $path"
                rm -f "$path"
                ;;
            *) : ;;   # foreign symlink, leave it
        esac
    fi
}

rm_dot_dir_symlink() {
    # Same as rm_dot_symlink but for symlinked directories (uses `rm` — no -r,
    # the link itself is what we want gone, not the target).
    rm_dot_symlink "$1"
}

unlink_zsh() {
    echo "Unlinking zsh configs..."
    rm_dot_symlink ~/.zshrc
    rm_dot_symlink ~/.zshenv
    rm_dot_symlink ~/.p10k.zsh
    # ~/.zshrc.local is user-owned, leave it
}

unlink_nvim() {
    echo "Unlinking nvim config..."
    rm_dot_dir_symlink ~/.config/nvim
}

unlink_ghostty() {
    echo "Unlinking ghostty config..."
    if [[ "$OS" == "macos" ]]; then
        rm_dot_symlink "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
    else
        rm_dot_symlink ~/.config/ghostty/config
    fi
}

unlink_zed() {
    echo "Unlinking zed config..."
    rm_dot_symlink ~/.config/zed/settings.json
    rm_dot_symlink ~/.config/zed/keymap.json
}

unlink_zellij() {
    echo "Unlinking zellij config..."
    rm_dot_symlink ~/.config/zellij/config.kdl
    rm_dot_dir_symlink ~/.config/zellij/layouts
}

unlink_herdr() {
    echo "Unlinking herdr config..."
    rm_dot_symlink ~/.config/herdr/config.toml
    rm_dot_dir_symlink ~/.config/herdr/plugins
}

unlink_comview() {
    echo "Unlinking comview config..."
    rm_dot_symlink ~/.config/comview/config.json
}

unlink_tmux() {
    echo "Unlinking tmux config..."
    rm_dot_symlink ~/.config/tmux/tmux.conf
    # TPM clone is user data, leave it in place
}

unlink_yazi() {
    echo "Unlinking yazi config..."
    for f in yazi.toml theme.toml keymap.toml init.lua package.toml; do
        rm_dot_symlink ~/.config/yazi/"$f"
    done
    if [ -d "$HOME/.config/yazi/plugins" ]; then
        for plugin in "$HOME"/.config/yazi/plugins/*/; do
            rm_dot_dir_symlink "${plugin%/}"
        done
    fi
}

unlink_agent_skills() {
    local dest="$1"
    [ -d "$dest" ] || return 0
    for item in "$dest"/*; do
        [ -e "$item" ] || continue
        rm_dot_dir_symlink "$item"
    done
}

unlink_agents() {
    echo "Unlinking shared agent skills..."
    unlink_agent_skills "$HOME/.agents/skills"
}

unlink_claude() {
    echo "Unlinking claude config..."
    rm -f ~/.claude/settings.json   # generated file
    rm_dot_symlink ~/.claude/CLAUDE.md
    rm_dot_symlink ~/.claude/mcp_settings.json
    unlink_agent_skills "$HOME/.agents/skills"
    unlink_agent_skills "$HOME/.claude/skills"
}

unlink_pi() {
    echo "Unlinking pi config..."
    rm_dot_symlink ~/.pi/agent/settings.json
    for kind in extensions prompts skills themes; do
        unlink_agent_skills "$HOME/.pi/agent/$kind"
    done
    unlink_agent_skills "$HOME/.agents/skills"
    if [ -L "$HOME/.pi/agent/vibes" ]; then
        rm_dot_dir_symlink "$HOME/.pi/agent/vibes"
    elif [ -d "$HOME/.pi/agent/vibes" ]; then
        for item in "$HOME"/.pi/agent/vibes/*; do
            [ -e "$item" ] && rm_dot_dir_symlink "$item"
        done
    fi
}

unlink_codex() {
    echo "Unlinking codex config..."
    rm_dot_dir_symlink ~/.codex
    unlink_agent_skills "$HOME/.agents/skills"
}

unlink_all() {
    unlink_zsh
    unlink_nvim
    unlink_ghostty
    unlink_zed
    unlink_zellij
    unlink_herdr
    unlink_comview
    unlink_tmux
    unlink_yazi
    unlink_agents
    unlink_claude
    unlink_pi
    unlink_codex
}

verb=link
$UNLINK && verb=unlink

if [ ${#COMPONENTS[@]} -eq 0 ]; then
    ${verb}_all
else
    for c in "${COMPONENTS[@]}"; do
        if ! declare -F "${verb}_$c" >/dev/null; then
            echo "Unknown component: $c" >&2
            exit 1
        fi
        "${verb}_$c"
    done
fi
