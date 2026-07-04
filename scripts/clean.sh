#!/bin/bash
# Uninstall counterpart to install.sh. Same component names, same INSTALL_ONLY,
# same --slim flag semantics. Per-component removers are best-effort: missing
# tools just warn-and-skip so this is safe to re-run.
#
# Guardrails: zsh (if it's your $SHELL), brew (if formulas remain).
#
#   INSTALL_ONLY=nvim,yazi scripts/clean.sh          # remove those brew formulas
#   INSTALL_ONLY=fzf,nvim scripts/clean.sh --slim    # slim-path removers
#   INSTALL_ONLY=zsh scripts/clean.sh --force-shell  # bypass zsh-is-my-shell guard
set -e

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
SLIM=false
ASSUME_YES=false
FORCE=false
FORCE_SHELL=false
LIST_COMPONENTS=false

# Keep in sync with scripts/install.sh and scripts/picker/main.go.
BREW_COMPONENTS=(brew git nvim fzf ripgrep fd bat gh tmux zellij zsh lazygit sqlite3 yazi hunk imagemagick docker zed ghostty tailscale rust mise bun uv zinit node link)
SLIM_COMPONENTS=(apt-core gh fzf nvim yazi hunk herdr bun uv mise zinit node link)

usage() {
    cat <<'USAGE'
Usage: clean.sh [--slim|-s] [--yes] [--force] [--force-shell] [--list-components]

Uninstalls components installed by install.sh. Requires INSTALL_ONLY=<list>.

  --slim, -s          use slim-path removers (mirrors install.sh --slim)
  --yes               skip the tty confirmation prompt
  --force             bypass the brew "formulas still installed" guard
  --force-shell       bypass the "$SHELL is zsh" guard
  --list-components   print components for the selected path and exit

Env:
  INSTALL_ONLY=a,b,c  components to remove (required). See --list-components.
USAGE
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --slim|-s)         SLIM=true; shift ;;
        --yes)             ASSUME_YES=true; shift ;;
        --force)           FORCE=true; shift ;;
        --force-shell)     FORCE_SHELL=true; shift ;;
        --list-components) LIST_COMPONENTS=true; shift ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if $LIST_COMPONENTS; then
    if $SLIM; then printf '%s\n' "${SLIM_COMPONENTS[@]}"
    else           printf '%s\n' "${BREW_COMPONENTS[@]}"
    fi
    exit 0
fi

INSTALL_ONLY="${INSTALL_ONLY:-}"
if [ -z "$INSTALL_ONLY" ]; then
    echo "error: INSTALL_ONLY=<comma,list> is required" >&2
    usage >&2
    exit 1
fi

if [[ "$OSTYPE" == "darwin"* ]]; then OS=macos; else OS=linux; fi

warn() { echo "[clean] WARNING: $*" >&2; }
say()  { echo "[clean] $*"; }

# --- plan preview / confirmation -----------------------------------------
requested=()
IFS=',' read -r -a requested <<< "$INSTALL_ONLY"
echo "Will remove: ${requested[*]}"
$SLIM && echo "(slim path)"
if [ -t 0 ] && ! $ASSUME_YES; then
    read -r -p 'proceed? [y/N] ' ans
    case "$ans" in y|Y|yes|YES) ;; *) echo aborted; exit 0 ;; esac
fi

# --- brew helpers --------------------------------------------------------
# Component name -> brew formula name (mirrors install.sh).
declare -A BREW_ALIAS=(
    [git]=git [nvim]=neovim [fzf]=fzf [ripgrep]=ripgrep [fd]=fd [bat]=bat
    [gh]=gh [tmux]=tmux [zellij]=zellij [zsh]=zsh [lazygit]=lazygit
    [sqlite3]=sqlite [yazi]=yazi [hunk]=hunk [imagemagick]=imagemagick
)

brew_uninstall() {
    local comp="$1" formula="${BREW_ALIAS[$1]:-$1}"
    if ! command -v brew >/dev/null 2>&1; then
        warn "$comp: brew not on PATH; skipping"
        return
    fi
    if ! brew list --formula "$formula" >/dev/null 2>&1; then
        say "$comp ($formula): not installed via brew, skipping"
        return
    fi
    say "uninstalling brew formula $formula"
    brew uninstall "$formula" || warn "$comp: brew uninstall failed"
}

brew_cask_uninstall() {
    local cask="$1"
    if ! command -v brew >/dev/null 2>&1; then
        warn "$cask: brew not on PATH; skipping"
        return
    fi
    brew uninstall --cask "$cask" 2>/dev/null || warn "$cask: brew uninstall --cask failed (may not be installed)"
}

# --- component removers --------------------------------------------------
remove_brew_formula() { brew_uninstall "$1"; }

remove_brew() {
    # Refuse to nuke the manager while it still owns other formulas, unless --force.
    if command -v brew >/dev/null 2>&1; then
        local remaining
        remaining="$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')"
        if [ "${remaining:-0}" -gt 0 ] && ! $FORCE; then
            warn "brew still has $remaining formula(s); refusing to uninstall. use --force to override."
            return
        fi
        say "running Homebrew uninstall..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" || warn "brew uninstaller failed"
    else
        warn "brew not installed, skipping"
    fi
}

remove_zsh() {
    if [[ "$SHELL" == *zsh* ]] && ! $FORCE_SHELL; then
        warn "\$SHELL is zsh ($SHELL); refusing to remove."
        warn "    switch first: chsh -s /bin/bash \$USER   (then re-run with --force-shell)"
        return
    fi
    if $SLIM; then
        warn "zsh under slim path is apt-managed; run: sudo apt-get remove -y zsh"
    else
        brew_uninstall zsh
    fi
}

remove_docker() {
    if [ "$OS" = macos ]; then
        brew_cask_uninstall docker
    else
        say "removing docker apt packages..."
        sudo apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null \
            || warn "docker apt remove failed (already gone or installed differently)"
    fi
}

remove_zed() {
    if [ "$OS" = macos ]; then
        brew_cask_uninstall zed
    else
        say "removing ~/.local/zed.app + ~/.local/bin/zed"
        rm -rf "$HOME/.local/zed.app" "$HOME/.local/bin/zed"
    fi
}

remove_ghostty() {
    if [ "$OS" = macos ]; then
        brew_cask_uninstall ghostty
    else
        warn "ghostty: Linux install is distro-specific; remove manually"
    fi
}

remove_tailscale() {
    sudo tailscale down 2>/dev/null || true
    if [ "$OS" = macos ]; then
        brew_uninstall tailscale
    else
        sudo apt-get remove -y tailscale 2>/dev/null || warn "tailscale apt remove failed"
    fi
}

remove_rust() {
    if command -v rustup >/dev/null 2>&1; then
        say "rustup self uninstall..."
        rustup self uninstall -y || warn "rustup self-uninstall failed"
    else
        say "rustup not present; removing ~/.cargo ~/.rustup"
        rm -rf "$HOME/.cargo" "$HOME/.rustup"
    fi
}

remove_mise() {
    if command -v mise >/dev/null 2>&1; then
        # mise's own uninstaller — fall back to manual if not supported.
        mise self-uninstall -y 2>/dev/null || mise self-uninstall 2>/dev/null || {
            say "mise self-uninstall not supported; removing binary + config"
            rm -f "$HOME/.local/bin/mise"
            rm -rf "$HOME/.config/mise" "$HOME/.local/share/mise"
        }
    else
        rm -f "$HOME/.local/bin/mise"
        rm -rf "$HOME/.config/mise" "$HOME/.local/share/mise"
    fi
}

remove_bun() {
    rm -rf "$HOME/.bun"
    warn "bun: PATH/completion lines may still be present in ~/.zshrc / ~/.bashrc"
}

remove_uv() {
    if command -v uv >/dev/null 2>&1 && uv self --help >/dev/null 2>&1; then
        uv self uninstall 2>/dev/null || rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"
    else
        rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"
    fi
}

remove_zinit() {
    rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/zinit"
}

remove_node() {
    if command -v mise >/dev/null 2>&1; then
        mise uninstall node@lts 2>/dev/null || true
        mise unuse -g node@lts 2>/dev/null || true
    else
        warn "node: mise not present; nothing to do (was it installed some other way?)"
    fi
}

remove_link() {
    say "unlinking dotfile symlinks..."
    "$DOTFILES/scripts/link.sh" --unlink
}

# slim-path binary removers (files in ~/.local/bin)
remove_bin() { rm -f "$HOME/.local/bin/$1"; }

remove_apt_core() {
    warn "apt-core: refusing to remove system tools (git/fd/bat/ripgrep/curl/unzip). Do that manually if you really want."
}

remove_slim_gh()    { sudo apt-get remove -y gh 2>/dev/null || warn "gh apt remove failed"; }
remove_slim_fzf()   { remove_bin fzf; }
remove_slim_nvim()  { remove_bin nvim; rm -f "$HOME/.local/share/man/man1/nvim.1" 2>/dev/null || true; }
remove_slim_yazi()  { remove_bin yazi; remove_bin ya; }
remove_slim_hunk()  { remove_bin hunk; remove_bin hunkdiff; }
remove_slim_herdr() { remove_bin herdr; }

# --- dispatch ------------------------------------------------------------
dispatch_brew() {
    local c="$1"
    case "$c" in
        brew) remove_brew ;;
        zsh)  remove_zsh ;;
        docker) remove_docker ;;
        zed)    remove_zed ;;
        ghostty) remove_ghostty ;;
        tailscale) remove_tailscale ;;
        rust) remove_rust ;;
        mise) remove_mise ;;
        bun)  remove_bun ;;
        uv)   remove_uv ;;
        zinit) remove_zinit ;;
        node)  remove_node ;;
        link)  remove_link ;;
        git|nvim|fzf|ripgrep|fd|bat|gh|tmux|zellij|lazygit|sqlite3|yazi|hunk|imagemagick)
            remove_brew_formula "$c" ;;
        *) warn "unknown brew-path component: $c" ;;
    esac
}

dispatch_slim() {
    local c="$1"
    case "$c" in
        apt-core) remove_apt_core ;;
        gh)    remove_slim_gh ;;
        fzf)   remove_slim_fzf ;;
        nvim)  remove_slim_nvim ;;
        yazi)  remove_slim_yazi ;;
        hunk)  remove_slim_hunk ;;
        herdr) remove_slim_herdr ;;
        bun)   remove_bun ;;
        uv)    remove_uv ;;
        mise)  remove_mise ;;
        zinit) remove_zinit ;;
        node)  remove_node ;;
        link)  remove_link ;;
        *) warn "unknown slim-path component: $c" ;;
    esac
}

# Order matters: run `brew` last so per-formula uninstalls happen first and
# clear the guard. `link` also runs late so config dirs are gone before we
# potentially yank the tool that consumes them.
ordered_run() {
    local comps=("$@") tail=() head=()
    for c in "${comps[@]}"; do
        case "$c" in
            brew|link) tail+=("$c") ;;
            *)         head+=("$c") ;;
        esac
    done
    for c in "${head[@]}" "${tail[@]}"; do
        echo
        echo "-- $c --"
        if $SLIM; then dispatch_slim "$c"; else dispatch_brew "$c"; fi
    done
}

ordered_run "${requested[@]}"

echo
say "done. Review shell rc files (~/.zshrc, ~/.bashrc) for lingering PATH/completion lines."
