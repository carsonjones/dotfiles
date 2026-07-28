#!/bin/bash
set -e

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
[ -n "$DOTFILES" ] || { echo "error: DOTFILES unset, refusing to link" >&2; exit 1; }
MINIMAL=false
SLIM=false
LIST_COMPONENTS=false

# Components installed by each provisioning path. Keep in sync with
# scripts/picker/main.go (the TUI hardcodes the same lists).
BREW_COMPONENTS=(brew git nvim fzf ripgrep fd bat gh tmux zellij zsh lazygit sqlite3 yazi hunk imagemagick docker zed ghostty tailscale rust mise bun uv zinit node link herdr-plugins)
SLIM_COMPONENTS=(apt-core gh fzf nvim yazi hunk herdr bun uv mise zinit node link)

usage() {
    cat <<'USAGE'
Usage: install.sh [--minimal|-m] [--slim|-s] [--list-components]

Provisions tools (Homebrew or apt/curl) and links dotfile configs.
Use scripts/link.sh directly when you only need to refresh symlinks.

  --minimal, -m       skip desktop apps and heavy nvim plugins
  --slim, -s          apt/curl tools instead of Homebrew (Linux only; implies --minimal)
  --list-components   print components for the selected path and exit

Env:
  INSTALL_ONLY=a,b,c  install only the named components (see --list-components).
                      When set, mode gating (--minimal) is ignored; the caller
                      is responsible for picking a coherent set.
USAGE
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --minimal|-m)
            MINIMAL=true
            shift
            ;;
        --slim|-s)
            # provision a curated tool set the Linux-native way
            # (apt/curl/release binaries — no Homebrew), then link configs.
            # Implies --minimal (no desktop apps / heavy nvim plugins).
            SLIM=true
            MINIMAL=true
            shift
            ;;
        --list-components)
            LIST_COMPONENTS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if $LIST_COMPONENTS; then
    if $SLIM; then
        printf '%s\n' "${SLIM_COMPONENTS[@]}"
    else
        printf '%s\n' "${BREW_COMPONENTS[@]}"
    fi
    exit 0
fi

# --- component gating -------------------------------------------------------
# `want X` is true when INSTALL_ONLY is unset (preset mode, install everything
# the mode calls for) OR when X appears in the comma-separated INSTALL_ONLY.
INSTALL_ONLY="${INSTALL_ONLY:-}"
custom_mode() { [ -n "$INSTALL_ONLY" ]; }
want() {
    local name="$1"
    if [ -z "$INSTALL_ONLY" ]; then
        return 0
    fi
    case ",$INSTALL_ONLY," in
        *,"$name",*) return 0 ;;
        *) return 1 ;;
    esac
}
# In preset mode we honor --minimal (skip heavy stuff). In custom mode the user
# has opted into an explicit component list; we don't second-guess them.
heavy_ok() { custom_mode || ! $MINIMAL; }

echo "Installing dotfiles from $DOTFILES"
custom_mode && echo "(custom mode: INSTALL_ONLY=$INSTALL_ONLY)"
$MINIMAL && ! custom_mode && echo "(minimal mode - skipping desktop apps and heavy plugins)"
$SLIM && echo "(slim mode: apt/curl tools, no Homebrew)"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

if $SLIM; then
    ########################################
    # tool set via apt + official curl installers + GitHub release binaries.
    ########################################
    [ "$OS" = "linux" ] || { echo "error: --slim is Linux-only (got $OS)" >&2; exit 1; }

    LOCAL_BIN="$HOME/.local/bin"
    mkdir -p "$LOCAL_BIN"
    export PATH="$LOCAL_BIN:$PATH"

    # apt packages (best-effort; never abort the whole bootstrap on one failure)
    if want apt-core && command -v apt-get &>/dev/null; then
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
    if want gh && ! command -v gh &>/dev/null; then
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
    if want fzf && ! fzf --zsh &>/dev/null; then
        echo "Installing fzf (release binary)..."
        {
            ver="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/junegunn/fzf/releases/latest | sed 's#.*/tag/v##')"
            curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${ver}/fzf-${ver}-linux_amd64.tar.gz" \
                | tar -xz -C "$LOCAL_BIN"
        } || echo "[dotfiles] WARNING: fzf install failed"
    fi

    # neovim — release tarball (apt's nvim is too old for this config)
    if want nvim && ! command -v nvim &>/dev/null; then
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
    if want yazi && ! command -v yazi &>/dev/null; then
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
    if want hunk && ! command -v hunk &>/dev/null; then
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
    if want herdr && ! command -v herdr &>/dev/null; then
        echo "Installing herdr..."
        curl -fsSL https://herdr.dev/install.sh | sh || echo "[dotfiles] WARNING: herdr install failed"
    fi

    # bun + uv — official curl installers
    if want bun && ! command -v bun &>/dev/null; then
        echo "Installing bun..."
        curl -fsSL https://bun.sh/install | bash || echo "[dotfiles] WARNING: bun install failed"
    fi
    if want uv && ! command -v uv &>/dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh || echo "[dotfiles] WARNING: uv install failed"
    fi
else
    # Install homebrew (macos) or linuxbrew — required for any brew formula below.
    if want brew; then
        if ! command -v brew &> /dev/null; then
            echo "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
                eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            fi
        fi
    fi

    # Collect selected brew formulas and install in one shot.
    # Component name → formula name (component name is what the picker/user sees).
    # Plain case instead of `declare -A`: macOS ships bash 3.2 (no assoc arrays).
    brew_alias() {
        case "$1" in
            nvim) echo neovim ;;
            sqlite3) echo sqlite ;;
            *) echo "$1" ;;
        esac
    }
    to_install=()
    for comp in git nvim fzf ripgrep fd bat gh tmux zellij zsh lazygit sqlite3 yazi hunk; do
        want "$comp" && to_install+=("$(brew_alias "$comp")")
    done
    if [ ${#to_install[@]} -gt 0 ]; then
        command -v brew &>/dev/null || { echo "error: brew not on PATH; include 'brew' in your selection or install Homebrew first" >&2; exit 1; }
        echo "Installing brew formulas: ${to_install[*]}"
        brew install "${to_install[@]}"
    fi

    # Set zsh as default shell (only when zsh was in the selection).
    if want zsh && [[ "$SHELL" != *"zsh"* ]]; then
        echo "Setting zsh as default shell..."
        ZSH_PATH=$(command -v zsh)
        if ! grep -q "$ZSH_PATH" /etc/shells; then
            echo "$ZSH_PATH" | sudo tee -a /etc/shells
        fi
        sudo chsh -s "$ZSH_PATH" "$USER"
    fi

    # Bun
    if want bun && ! command -v bun &> /dev/null; then
        echo "Installing Bun..."
        curl -fsSL https://bun.sh/install | bash
    fi

    # uv (fast python package manager)
    if want uv && ! command -v uv &> /dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
fi

# Heavy neovim dependencies (skip in preset minimal mode; brew path only)
if ! $SLIM && want imagemagick && heavy_ok; then
    brew install imagemagick
fi

# Desktop apps (skip in preset minimal mode; brew path only)
if ! $SLIM && heavy_ok; then
    # Docker
    if want docker && ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        if [[ "$OS" == "macos" ]]; then
            brew install --cask docker
        else
            curl -fsSL https://get.docker.com | sh
        fi
    fi

    # Zed
    if want zed && ! command -v zed &> /dev/null; then
        echo "Installing Zed..."
        if [[ "$OS" == "macos" ]]; then
            brew install --cask zed
        else
            curl -f https://zed.dev/install.sh | sh
        fi
    fi

    # Ghostty
    if want ghostty && ! command -v ghostty &> /dev/null; then
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
    if want tailscale && ! command -v tailscale &> /dev/null; then
        echo "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi

    # Rust/Cargo
    if want rust && ! command -v cargo &> /dev/null; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
fi

# mise for version management (replaces asdf)
if want mise && ! command -v mise &>/dev/null && [ ! -x "$HOME/.local/bin/mise" ]; then
    echo "Installing mise..."
    curl -fsSL https://mise.run | sh
fi

# zinit (zsh plugin manager)
if want zinit; then
    ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
    if [ ! -d "$ZINIT_HOME" ]; then
        echo "Installing zinit..."
        mkdir -p "$(dirname $ZINIT_HOME)"
        git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
    fi
fi

# Link all configs. Extracted to scripts/link.sh so a machine that only needs a
# refresh (no tool installs) can run that directly: scripts/link.sh [--minimal] [components...]
if want link; then
    LINK_ARGS=()
    $MINIMAL && LINK_ARGS+=(--minimal)
    MINIMAL=$MINIMAL "$DOTFILES/scripts/link.sh" "${LINK_ARGS[@]}"
fi

# herdr external plugins — pulled from GitHub via herdr's own plugin manager into
# $DOTFILES/herdr/plugins/github (tracked once installed). Runs after the link
# step above since it needs ~/.config/herdr/plugins symlinked into the repo first.
HERDR_PLUGINS=(
    cloudmanic/herdr-plus
    thanhdat77/herdr-picker-plus
    JanTvrdik/herdr-command-palette
    carsonjones/herdr-agent-dashboard
    iurysza/termscope
)
if ! $SLIM && want herdr-plugins && command -v herdr &>/dev/null; then
    have_herdr_plugin() {
        local owner="${1%%/*}" repo="${1##*/}"
        if command -v jq &>/dev/null; then
            herdr plugin list --json 2>/dev/null | jq -e --arg o "$owner" --arg r "$repo" \
                '.result.plugins[]?.source | select(.kind=="github" and .owner==$o and .repo==$r)' >/dev/null 2>&1
        else
            herdr plugin list --json 2>/dev/null | grep -q "\"owner\":\"$owner\",\"repo\":\"$repo\""
        fi
    }
    for repo in "${HERDR_PLUGINS[@]}"; do
        if have_herdr_plugin "$repo"; then
            continue
        fi
        echo "Installing herdr plugin $repo..."
        herdr plugin install "$repo" --yes || echo "[dotfiles] WARNING: herdr plugin install $repo failed"
    done
fi

# herdr local plugins — linked straight from this repo, no external fetch.
# `herdr plugin link` re-points the registration in place, so safe to re-run.
HERDR_LOCAL_PLUGINS=(tiles)
if want herdr-plugins && command -v herdr &>/dev/null; then
    for name in "${HERDR_LOCAL_PLUGINS[@]}"; do
        echo "Linking herdr plugin $name..."
        herdr plugin link "$DOTFILES/herdr/plugins/$name" || echo "[dotfiles] WARNING: herdr plugin link $name failed"
    done
fi

# Cursor config (template - needs manual setup)
if ! $MINIMAL && ! custom_mode; then
    echo "Cursor MCP template at $DOTFILES/cursor/mcp.json.template"
    echo "Copy to ~/.cursor/mcp.json and fill in API keys"
fi

# Node.js via mise (optional)
if want node; then
    MISE_BIN="$(command -v mise || true)"
    [ -z "$MISE_BIN" ] && [ -x "$HOME/.local/bin/mise" ] && MISE_BIN="$HOME/.local/bin/mise"
    if [ -n "$MISE_BIN" ]; then
        if ! "$MISE_BIN" ls node 2>/dev/null | grep -q .; then
            echo "Installing Node.js via mise..."
            "$MISE_BIN" use -g node@lts
        fi
    fi
fi

echo ""
echo "Done! Next steps:"
echo "1. Source zshrc: source ~/.zshrc"
echo "2. Edit ~/.zshrc.local with secrets"
echo "3. Run :Lazy in nvim to install plugins"
if ! $MINIMAL && ! custom_mode; then
    echo "4. Start tailscale: sudo tailscale up"
fi
