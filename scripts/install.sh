#!/bin/bash
set -e

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
MINIMAL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --minimal|-m)
            MINIMAL=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: install.sh [--minimal]"
            exit 1
            ;;
    esac
done

echo "Installing dotfiles from $DOTFILES"
$MINIMAL && echo "(minimal mode - skipping desktop apps and heavy plugins)"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

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
brew install git neovim fzf zoxide ripgrep fd bat gh tmux zsh lazygit sqlite3

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

# asdf for version management
if [ ! -d "$HOME/.asdf" ]; then
    echo "Installing asdf..."
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
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

# Link tmux config
echo "Linking tmux config..."
mkdir -p ~/.config/tmux
ln -sf "$DOTFILES/tmux/tmux.conf" ~/.config/tmux/tmux.conf

# Install TPM if not present
if [ ! -d ~/.config/tmux/plugins/tpm ]; then
    echo "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
fi

# Link claude config
echo "Linking claude config..."
mkdir -p ~/.claude
ln -sf "$DOTFILES/claude/settings.json" ~/.claude/settings.json
ln -sf "$DOTFILES/claude/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$DOTFILES/claude/mcp_settings.json" ~/.claude/mcp_settings.json

# Cursor config (template - needs manual setup)
if ! $MINIMAL; then
    echo "Cursor MCP template at $DOTFILES/cursor/mcp.json.template"
    echo "Copy to ~/.cursor/mcp.json and fill in API keys"
fi

# Node.js via asdf (optional)
if [ -d "$HOME/.asdf" ]; then
    source "$HOME/.asdf/asdf.sh"
    if ! asdf plugin list | grep -q nodejs; then
        echo "Adding nodejs plugin to asdf..."
        asdf plugin add nodejs
        asdf install nodejs latest
        asdf global nodejs latest
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
