#!/bin/bash
# Manage machine-local nvim plugin overrides (nvim/lua/local.lua, git-ignored).
#
#   scripts/nvim-disable.sh                     # print list from a TTY, else no-op
#   scripts/nvim-disable.sh --list              # key<TAB>state<TAB>source-file
#   scripts/nvim-disable.sh --disable <key>     # add to disabled map, rewrite local.lua
#   scripts/nvim-disable.sh --enable  <key>     # remove from disabled map, rewrite local.lua
#
# Plugin keys are discovered by scanning nvim/lua/plugins/*.lua for the pattern
#   vim.g.local_disabled_plugins and vim.g.local_disabled_plugins['<key>']
# so a plugin becomes toggleable simply by adding that guard to its spec.
set -e

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
PLUGINS_DIR="$DOTFILES/nvim/lua/plugins"
LOCAL_LUA="$DOTFILES/nvim/lua/local.lua"

usage() {
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

# Emit "<key>\t<source-file>" for every toggleable plugin in nvim/lua/plugins.
scan_keys() {
    [ -d "$PLUGINS_DIR" ] || return 0
    grep -Hn "vim.g.local_disabled_plugins\['" "$PLUGINS_DIR"/*.lua 2>/dev/null \
        | sed -nE "s|^([^:]+):[0-9]+:.*vim\\.g\\.local_disabled_plugins\\['([^']+)'\\].*|\\2\\t\\1|p" \
        | sort -u
}

# Print keys currently marked disabled in local.lua (uncommented `['<key>'] = true` lines).
current_disabled() {
    [ -f "$LOCAL_LUA" ] || return 0
    sed -nE "s|^[[:space:]]*\\['([^']+)'\\][[:space:]]*=[[:space:]]*true.*|\\1|p" "$LOCAL_LUA"
}

# Rewrite local.lua from a newline-separated list of disabled keys on stdin.
# All known keys are emitted; disabled ones as live entries, others as
# commented-out placeholders so users see what's available to hand-edit.
rewrite_local() {
    local disabled_file="$1"
    local tmp k _s
    tmp="$(mktemp)"
    {
        echo '-- machine-local nvim overrides (git-ignored). Managed by scripts/nvim-disable.sh.'
        echo 'vim.g.local_disabled_plugins = {'
        while IFS=$'\t' read -r k _s; do
            [ -n "$k" ] || continue
            if grep -Fxq "$k" "$disabled_file"; then
                printf "    ['%s'] = true,\n" "$k"
            else
                printf "    -- ['%s'] = true,\n" "$k"
            fi
        done < <(scan_keys)
        echo '}'
    } > "$tmp"
    mv "$tmp" "$LOCAL_LUA"
}

cmd_list() {
    local disabled
    disabled="$(current_disabled || true)"
    while IFS=$'\t' read -r key src; do
        [ -n "$key" ] || continue
        local state='enabled'
        if printf '%s\n' "$disabled" | grep -Fxq "$key"; then
            state='disabled'
        fi
        printf '%s\t%s\t%s\n' "$key" "$state" "${src#$DOTFILES/}"
    done < <(scan_keys)
}

cmd_set() {
    local action="$1" key="$2"
    [ -n "$key" ] || { echo "error: --$action requires a plugin key" >&2; exit 1; }
    # Sanity check: refuse unknown keys so typos surface.
    if ! scan_keys | awk -F'\t' '{print $1}' | grep -Fxq "$key"; then
        echo "error: unknown plugin key '$key' (see --list)" >&2
        exit 1
    fi
    local tmp
    tmp="$(mktemp)"
    current_disabled > "$tmp" || true
    case "$action" in
        disable) grep -Fxq "$key" "$tmp" || echo "$key" >> "$tmp" ;;
        enable)  grep -Fxv "$key" "$tmp" > "$tmp.new" || true; mv "$tmp.new" "$tmp" ;;
    esac
    rewrite_local "$tmp"
    rm -f "$tmp"
    echo "[$action] $key"
}

if [ $# -eq 0 ]; then
    if [ -t 1 ]; then
        cmd_list
        echo
        echo 'hint: --disable <key> / --enable <key>'
    fi
    exit 0
fi

case "$1" in
    --list) cmd_list ;;
    --disable) cmd_set disable "$2" ;;
    --enable)  cmd_set enable  "$2" ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
esac
