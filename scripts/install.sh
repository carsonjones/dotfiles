#!/bin/bash
set -e

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
[ -n "$DOTFILES" ] || { echo "error: DOTFILES unset, refusing to link" >&2; exit 1; }
MINIMAL=false
SKIMM=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --minimal|-m)
            MINIMAL=true
            shift
            ;;
        --skimm)
            # provision a curated tool set the Linux-native way
            # (apt/curl/release binaries — no Homebrew), then link configs.
            # Implies --minimal (no desktop apps / heavy nvim plugins).
            SKIMM=true
            MINIMAL=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: install.sh [--minimal] [--skimm]"
            exit 1
            ;;
    esac
done

echo "Installing dotfiles from $DOTFILES"
$MINIMAL && echo "(minimal mode - skipping desktop apps and heavy plugins)"
$SKIMM && echo "(skimm mode: apt/curl tools, no Homebrew)"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

if $SKIMM; then
    ########################################
    # tool set via apt + official curl installers + GitHub release binaries.
    ########################################
    [ "$OS" = "linux" ] || { echo "error: --skimm is Linux-only (got $OS)" >&2; exit 1; }

    LOCAL_BIN="$HOME/.local/bin"
    mkdir -p "$LOCAL_BIN"
    export PATH="$LOCAL_BIN:$PATH"

    # apt packages (best-effort; never abort the whole bootstrap on one failure)
    if command -v apt-get &>/dev/null; then
        echo "Installing apt packages (ripgrep, fd, bat, git, unzip)..."
        sudo apt-get update -y || true
        # NOTE: fzf is NOT installed via apt — Ubuntu's fzf predates `fzf --zsh`
        # (added in 0.48.0), which zsh/zshrc needs for the Ctrl-R history widget.
        # It's installed from a GitHub release below instead.
        sudo apt-get install -y git fd-find bat ripgrep unzip curl ca-certificates tar || true
        # Ubuntu ships these under alternate names; expose canonical ones
        [ -x /usr/bin/fdfind ] && ln -sf /usr/bin/fdfind "$LOCAL_BIN/fd"
        [ -x /usr/bin/batcat ] && ln -sf /usr/bin/batcat "$LOCAL_BIN/bat"
    fi

    # gh — official apt repo (release asset names are version-pinned, so apt is cleaner)
    if ! command -v gh &>/dev/null; then
        echo "Installing gh (GitHub CLI)..."
        {
            sudo mkdir -p -m 755 /etc/apt/keyrings
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
            sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
            sudo apt-get update -y && sudo apt-get install -y gh
        } || echo "[dotfiles] WARNING: gh install failed"
    fi

    # fzf — release binary (apt's fzf predates `fzf --zsh`, needed for the
    # Ctrl-R history widget in zsh/zshrc). The `fzf --zsh` guard also catches a
    # stale apt fzf left over from a previous bootstrap, not just a missing one.
    if ! fzf --zsh &>/dev/null; then
        echo "Installing fzf (release binary)..."
        {
            ver="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/junegunn/fzf/releases/latest | sed 's#.*/tag/v##')"
            curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${ver}/fzf-${ver}-linux_amd64.tar.gz" \
                | tar -xz -C "$LOCAL_BIN"
        } || echo "[dotfiles] WARNING: fzf install failed"
    fi

    # neovim — release tarball (apt's nvim is too old for this config)
    if ! command -v nvim &>/dev/null; then
        echo "Installing neovim (release tarball)..."
        {
            tmp="$(mktemp -d)"
            curl -fsSL https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz \
                | tar -xz -C "$tmp"
            cp -rf "$tmp"/nvim-linux-x86_64/* "$HOME/.local/"
            rm -rf "$tmp"
        } || echo "[dotfiles] WARNING: neovim install failed"
    fi

    # yazi — release zip (provides `ya` + `yazi`)
    if ! command -v yazi &>/dev/null; then
        echo "Installing yazi (release zip)..."
        {
            tmp="$(mktemp -d)"
            curl -fsSL https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip -o "$tmp/yazi.zip"
            unzip -q "$tmp/yazi.zip" -d "$tmp"
            find "$tmp" -type f \( -name ya -o -name yazi \) -exec cp {} "$LOCAL_BIN/" \;
            rm -rf "$tmp"
        } || echo "[dotfiles] WARNING: yazi install failed"
    fi

    # hunk — release tarball (modem-dev/hunk; asset name is version-agnostic)
    if ! command -v hunk &>/dev/null; then
        echo "Installing hunk (release tarball)..."
        {
            tmp="$(mktemp -d)"
            curl -fsSL https://github.com/modem-dev/hunk/releases/latest/download/hunkdiff-linux-x64.tar.gz \
                | tar -xz -C "$tmp"
            find "$tmp" -maxdepth 2 -type f -perm -u+x -exec cp {} "$LOCAL_BIN/" \;
            rm -rf "$tmp"
        } || echo "[dotfiles] WARNING: hunk install failed"
    fi

    # herdr — official Linux installer (Rust; installs to ~/.local/bin)
    if ! command -v herdr &>/dev/null; then
        echo "Installing herdr..."
        curl -fsSL https://herdr.dev/install.sh | sh || echo "[dotfiles] WARNING: herdr install failed"
    fi

    # bun + uv — official curl installers
    if ! command -v bun &>/dev/null; then
        echo "Installing bun..."
        curl -fsSL https://bun.sh/install | bash || echo "[dotfiles] WARNING: bun install failed"
    fi
    if ! command -v uv &>/dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh || echo "[dotfiles] WARNING: uv install failed"
    fi
else
    # Install homebrew (macos) or linuxbrew
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add brew to PATH for this script
        if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        fi
    fi

    # Core tools (always installed)
    echo "Installing core tools..."
    brew install git neovim fzf ripgrep fd bat gh tmux zellij zsh lazygit sqlite3

    # Set zsh as default shell
    if [[ "$SHELL" != *"zsh"* ]]; then
        echo "Setting zsh as default shell..."
        ZSH_PATH=$(which zsh)
        if ! grep -q "$ZSH_PATH" /etc/shells; then
            echo "$ZSH_PATH" | sudo tee -a /etc/shells
        fi
        sudo chsh -s "$ZSH_PATH" "$USER"
    fi

    # Bun
    if ! command -v bun &> /dev/null; then
        echo "Installing Bun..."
        curl -fsSL https://bun.sh/install | bash
    fi

    # uv (fast python package manager)
    if ! command -v uv &> /dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
fi

# Heavy neovim dependencies (skip in minimal mode)
if ! $MINIMAL; then
    brew install imagemagick
fi

# Desktop apps (skip in minimal mode)
if ! $MINIMAL; then
    # Docker
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        if [[ "$OS" == "macos" ]]; then
            brew install --cask docker
        else
            curl -fsSL https://get.docker.com | sh
        fi
    fi

    # Zed
    if ! command -v zed &> /dev/null; then
        echo "Installing Zed..."
        if [[ "$OS" == "macos" ]]; then
            brew install --cask zed
        else
            curl -f https://zed.dev/install.sh | sh
        fi
    fi

    # Ghostty
    if ! command -v ghostty &> /dev/null; then
        echo "Installing Ghostty..."
        if [[ "$OS" == "macos" ]]; then
            brew install --cask ghostty
        else
            if command -v apt &> /dev/null; then
                echo "Ghostty: check https://ghostty.org/docs/install/binary#linux for your distro"
            elif command -v dnf &> /dev/null; then
                sudo dnf copr enable pgdev/ghostty -y && sudo dnf install ghostty -y
            elif command -v pacman &> /dev/null; then
                sudo pacman -S ghostty
            else
                echo "Ghostty: install manually from https://ghostty.org"
            fi
        fi
    fi

    # Tailscale
    if ! command -v tailscale &> /dev/null; then
        echo "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi

    # Rust/Cargo
    if ! command -v cargo &> /dev/null; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
fi

# mise for version management (replaces asdf)
if ! command -v mise &>/dev/null && [ ! -x "$HOME/.local/bin/mise" ]; then
    echo "Installing mise..."
    curl -fsSL https://mise.run | sh
fi

# zinit (zsh plugin manager)
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
    echo "Installing zinit..."
    mkdir -p "$(dirname $ZINIT_HOME)"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Link zsh configs
echo "Linking zsh configs..."
ln -sf "$DOTFILES/zsh/zshrc" ~/.zshrc
ln -sf "$DOTFILES/zsh/zshenv" ~/.zshenv
ln -sf "$DOTFILES/zsh/p10k.zsh" ~/.p10k.zsh

# Create .zshrc.local if not exists
if [ ! -f ~/.zshrc.local ]; then
    cp "$DOTFILES/zsh/zshrc.local.template" ~/.zshrc.local
    echo "Created ~/.zshrc.local - fill in your secrets"
fi

# Link nvim config
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

# Link ghostty config (skip in minimal mode)
if ! $MINIMAL; then
    echo "Linking ghostty config..."
    if [[ "$OS" == "macos" ]]; then
        mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"
        ln -sf "$DOTFILES/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
    else
        mkdir -p ~/.config/ghostty
        ln -sf "$DOTFILES/ghostty/config" ~/.config/ghostty/config
    fi

    # Link zed config
    echo "Linking zed config..."
    mkdir -p ~/.config/zed
    ln -sf "$DOTFILES/zed/settings.json" ~/.config/zed/settings.json
    ln -sf "$DOTFILES/zed/keymap.json" ~/.config/zed/keymap.json
fi

# Link zellij config (replaces prise)
echo "Linking zellij config..."
mkdir -p ~/.config/zellij
ln -sf "$DOTFILES/zellij/config.kdl" ~/.config/zellij/config.kdl
ln -sfn "$DOTFILES/zellij/layouts" ~/.config/zellij/layouts

# Link herdr config (terminal workspace manager for AI agents)
echo "Linking herdr config..."
mkdir -p ~/.config/herdr
ln -sfn "$DOTFILES/herdr/config.toml" ~/.config/herdr/config.toml

# Link comview config
echo "Linking comview config..."
mkdir -p ~/.config/comview
ln -sf "$DOTFILES/comview/config.json" ~/.config/comview/config.json

# Link tmux config
echo "Linking tmux config..."
mkdir -p ~/.config/tmux
ln -sf "$DOTFILES/tmux/tmux.conf" ~/.config/tmux/tmux.conf

# Link yazi config
echo "Linking yazi config..."
mkdir -p ~/.config/yazi
ln -sf "$DOTFILES/yazi/yazi.toml" ~/.config/yazi/yazi.toml
ln -sf "$DOTFILES/yazi/theme.toml" ~/.config/yazi/theme.toml
ln -sf "$DOTFILES/yazi/keymap.toml" ~/.config/yazi/keymap.toml
ln -sf "$DOTFILES/yazi/init.lua" ~/.config/yazi/init.lua
ln -sf "$DOTFILES/yazi/package.toml" ~/.config/yazi/package.toml
if command -v ya >/dev/null 2>&1; then
    ya pkg install >/dev/null 2>&1 || true
fi

# Install TPM if not present
if command -v tmux &>/dev/null && [ ! -d ~/.config/tmux/plugins/tpm ]; then
    echo "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
fi

# Link claude config
echo "Linking claude config..."
mkdir -p ~/.claude
ln -sf "$DOTFILES/claude/settings.json" ~/.claude/settings.json
ln -sf "$DOTFILES/claude/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$DOTFILES/claude/mcp_settings.json" ~/.claude/mcp_settings.json

# Link claude skills per-item (leaves other skills in ~/.claude/skills untouched)
if [ -d "$DOTFILES/claude/skills" ]; then
    mkdir -p ~/.claude/skills
    for item in "$DOTFILES"/claude/skills/*; do
        [ -e "$item" ] && ln -sfn "$item" "$HOME/.claude/skills/$(basename "$item")"
    done
fi

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

# Link codex config
echo "Linking codex config..."
ln -sfn "$DOTFILES/.codex" ~/.codex

# Cursor config (template - needs manual setup)
if ! $MINIMAL; then
    echo "Cursor MCP template at $DOTFILES/cursor/mcp.json.template"
    echo "Copy to ~/.cursor/mcp.json and fill in API keys"
fi

# Node.js via mise (optional)
MISE_BIN="$(command -v mise || true)"
[ -z "$MISE_BIN" ] && [ -x "$HOME/.local/bin/mise" ] && MISE_BIN="$HOME/.local/bin/mise"
if [ -n "$MISE_BIN" ]; then
    if ! "$MISE_BIN" ls node 2>/dev/null | grep -q .; then
        echo "Installing Node.js via mise..."
        "$MISE_BIN" use -g node@lts
    fi
fi

echo ""
echo "Done! Next steps:"
echo "1. Source zshrc: source ~/.zshrc"
echo "2. Edit ~/.zshrc.local with secrets"
echo "3. Run :Lazy in nvim to install plugins"
if ! $MINIMAL; then
    echo "4. Start tailscale: sudo tailscale up"
fi
