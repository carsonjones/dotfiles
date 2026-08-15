#!/bin/bash
# Refresh a machine after initial provisioning — idempotent, safe to re-run
# daily. Each section is best-effort: a failure in one manager doesn't abort
# the rest. See the summary at the end for what ran / was skipped / failed.
#
#   scripts/update.sh                     # pull, relink, refresh managers, restore lazy-lock.json
#   scripts/update.sh --upgrade-plugins   # run `Lazy! sync` instead (refreshes lazy-lock.json)
#   scripts/update.sh --dry-run           # print what would run, do nothing
set -e

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
UPGRADE_PLUGINS=false
DRY_RUN=false

usage() {
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --upgrade-plugins) UPGRADE_PLUGINS=true ;;
        --dry-run)         DRY_RUN=true ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# --- OS detection ---------------------------------------------------------
if [[ "$OSTYPE" == "darwin"* ]]; then OS=macos; else OS=linux; fi

# Source brew shellenv when running non-interactively so brew-managed tools
# (nvim, bun, tailscale, etc.) are visible even from a bare shell.
for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$brew_bin" ] && ! command -v brew >/dev/null 2>&1; then
        eval "$("$brew_bin" shellenv)"
        break
    fi
done
# Curl-installed tools that put binaries under $HOME.
for extra in "$HOME/.bun/bin" "$HOME/.cargo/bin" "$HOME/.local/bin"; do
    [ -d "$extra" ] && case ":$PATH:" in *":$extra:"*) ;; *) PATH="$extra:$PATH" ;; esac
done

# --- summary tracking -----------------------------------------------------
# Each section pushes into RAN / SKIPPED / FAILED (with an optional reason).
RAN=(); SKIPPED=(); FAILED=()
mark_ran()     { RAN+=("$1"); }
mark_skipped() { SKIPPED+=("$1${2:+ ($2)}"); }
mark_failed()  { FAILED+=("$1${2:+ ($2)}"); }

warn() { echo "[update] WARNING: $*" >&2; }
log()  { echo; echo "== $* =="; }

# Run a command best-effort, tracking the result under the given label.
# Usage: try <label> <cmd...>
try() {
    local label="$1"; shift
    if $DRY_RUN; then
        echo "[dry-run] $label: $*"
        mark_ran "$label (dry-run)"
        return 0
    fi
    if ( set +e; "$@" ); then
        mark_ran "$label"
    else
        warn "$label failed"
        mark_failed "$label"
    fi
}

# --- 1. git pull ----------------------------------------------------------
section_git() {
    log "git pull --ff-only ($DOTFILES)"
    if $DRY_RUN; then
        echo "[dry-run] git -C $DOTFILES pull --ff-only"
        mark_ran "git-pull (dry-run)"
        return
    fi
    if git -C "$DOTFILES" pull --ff-only; then
        mark_ran git-pull
    else
        warn "dotfiles is not fast-forward (diverged? uncommitted? offline?) — continuing"
        mark_failed git-pull "non-ff"
    fi
}

# --- 2. link.sh -----------------------------------------------------------
section_link() {
    log "scripts/link.sh"
    try link "$DOTFILES/scripts/link.sh"
}

# --- 3. package managers --------------------------------------------------
# GitHub-release binaries: refresh only if a newer tag is available.
# Reuses the same download flow as install.sh --slim.
LOCAL_BIN="$HOME/.local/bin"

# Latest tag from the redirect on /releases/latest (no auth, no jq).
gh_latest_tag() {
    curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" \
        | sed 's#.*/tag/##'
}

# Compare current --version output to latest tag; if different, run the updater fn.
refresh_release_bin() {
    local label="$1" bin="$2" repo="$3" update_fn="$4"
    if ! command -v "$bin" >/dev/null 2>&1; then
        mark_skipped "$label" "not installed"
        return
    fi
    if $DRY_RUN; then
        echo "[dry-run] check $repo latest tag; reinstall $bin if newer"
        mark_ran "$label (dry-run)"
        return
    fi
    local latest current
    latest="$(gh_latest_tag "$repo" 2>/dev/null || true)"
    current="$("$bin" --version 2>/dev/null | head -n1 || true)"
    if [ -z "$latest" ]; then
        warn "$label: could not determine latest tag; skipping"
        mark_skipped "$label" "no tag"
        return
    fi
    # Cheap match: tag string appears somewhere in --version. Not perfect but
    # good enough to avoid a re-download on every run; a false-negative just
    # re-downloads the same binary.
    local tag_num="${latest#v}"
    if [[ "$current" == *"$tag_num"* ]] || [[ "$current" == *"$latest"* ]]; then
        mark_skipped "$label" "up to date ($latest)"
        return
    fi
    echo "$label: $current -> $latest"
    if ( set +e; "$update_fn" ); then
        mark_ran "$label ($latest)"
    else
        warn "$label update failed"
        mark_failed "$label"
    fi
}

update_nvim() {
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz \
        | tar -xz -C "$tmp"
    cp -rf "$tmp"/nvim-linux-x86_64/* "$HOME/.local/"
    rm -rf "$tmp"
}

update_yazi() {
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip -o "$tmp/yazi.zip"
    unzip -q "$tmp/yazi.zip" -d "$tmp"
    find "$tmp" -type f \( -name ya -o -name yazi \) -exec cp {} "$LOCAL_BIN/" \;
    rm -rf "$tmp"
}

update_hunk() {
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL https://github.com/modem-dev/hunk/releases/latest/download/hunkdiff-linux-x64.tar.gz \
        | tar -xz -C "$tmp"
    find "$tmp" -maxdepth 2 -type f -perm -u+x -exec cp {} "$LOCAL_BIN/" \;
    rm -rf "$tmp"
}

update_fzf() {
    local ver; ver="$(gh_latest_tag junegunn/fzf | sed 's/^v//')"
    curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${ver}/fzf-${ver}-linux_amd64.tar.gz" \
        | tar -xz -C "$LOCAL_BIN"
}

update_herdr() {
    curl -fsSL https://herdr.dev/install.sh | sh
}

section_packages() {
    log "package managers"
    if command -v brew >/dev/null 2>&1; then
        try brew-update brew update
        try brew-upgrade brew upgrade
    else
        mark_skipped brew "not installed"
    fi

    # Only refresh release binaries when they live under ~/.local/bin
    # (i.e. we installed them via --slim, not brew).
    if [ "$OS" = linux ]; then
        maybe_refresh() {
            local label="$1" bin="$2" repo="$3" fn="$4"
            if [ -x "$LOCAL_BIN/$bin" ]; then
                refresh_release_bin "$label" "$bin" "$repo" "$fn"
            else
                mark_skipped "$label" "not slim-managed"
            fi
        }
        maybe_refresh nvim  nvim  neovim/neovim   update_nvim
        maybe_refresh yazi  yazi  sxyazi/yazi     update_yazi
        maybe_refresh hunk  hunk  modem-dev/hunk  update_hunk
        maybe_refresh fzf   fzf   junegunn/fzf    update_fzf
        maybe_refresh herdr herdr herdr-dev/herdr update_herdr
    fi
}

# --- 4. language toolchains ----------------------------------------------
section_toolchains() {
    log "language toolchains"

    if command -v bun >/dev/null 2>&1;    then try bun-upgrade bun upgrade;   else mark_skipped bun    "not installed"; fi

    if command -v uv >/dev/null 2>&1; then
        # `uv self update` is only available on installers that put uv under user control.
        if uv self --help >/dev/null 2>&1; then try uv-self-update uv self update
        else mark_skipped uv "no self-update on this build"; fi
    else mark_skipped uv "not installed"; fi

    if command -v mise >/dev/null 2>&1; then
        try mise-self-update mise self-update -y
        try mise-upgrade     mise upgrade
    else mark_skipped mise "not installed"; fi

    if command -v rustup >/dev/null 2>&1; then try rustup-update rustup update
    else mark_skipped rustup "not installed"; fi

    # brew's tailscale is a formula and gets picked up by `brew upgrade` above.
    if [ "$OS" = linux ] && command -v tailscale >/dev/null 2>&1; then
        try tailscale-update tailscale update --yes
    else mark_skipped tailscale "not linux or not installed"; fi
}

# --- 5. plugin ecosystems -------------------------------------------------
section_plugins() {
    log "plugin ecosystems"

    # zinit: needs an interactive zsh so its `zinit` function loads from zshrc.
    if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git" ]; then
        # Plugin updates can leave completion symlinks pointing at files that
        # upstream removed. Clear them before the next shell runs compinit.
        try zinit-update zsh -ic 'zinit self-update && zinit update --all; update_status=$?; zinit cclear; exit $update_status'
    else
        mark_skipped zinit "not installed"
    fi

    if command -v nvim >/dev/null 2>&1; then
        if $UPGRADE_PLUGINS; then
            try "nvim-lazy-sync" nvim --headless "+Lazy! sync" +qa
            echo
            echo "[update] --upgrade-plugins: review & commit refreshed lazy-lock.json"
            echo "[update] (and any updated treesitter parsers under nvim/)"
        else
            try "nvim-lazy-restore" nvim --headless "+Lazy! restore" +qa
        fi
    else
        mark_skipped nvim-plugins "nvim not installed"
    fi

    if command -v ya >/dev/null 2>&1; then try yazi-pkg ya pkg upgrade
    else mark_skipped yazi-pkg "ya not installed"; fi
}

# --- 6. summary -----------------------------------------------------------
print_summary() {
    echo
    echo "== update summary =="
    if [ ${#RAN[@]}     -gt 0 ]; then printf '  ran:     %s\n' "$(IFS=,; echo "${RAN[*]}")"; fi
    if [ ${#SKIPPED[@]} -gt 0 ]; then printf '  skipped: %s\n' "$(IFS=,; echo "${SKIPPED[*]}")"; fi
    if [ ${#FAILED[@]}  -gt 0 ]; then printf '  failed:  %s\n' "$(IFS=,; echo "${FAILED[*]}")"; fi
    [ ${#FAILED[@]} -eq 0 ] || return 1
}

section_git
section_link
section_packages
section_toolchains
section_plugins
print_summary
