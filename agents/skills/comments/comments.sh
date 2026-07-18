#!/usr/bin/env bash
# Helper for the /comments skill. Resolves the per-repo comment queue written by
# comments.nvim (<leader>hc) and reads or archives it.
#
#   comments.sh read           print the current repo's queued comments
#   comments.sh clear          archive the queue (recoverable) then truncate it
#   comments.sh path           print the queue file path
#   comments.sh dispatch [rel] [--clear]
#                              fire "/comments [rel] [--clear]" in an idle agent
#                              pane in the same herdr tab; silent no-op
#                              otherwise. --clear asks the receiving agent to
#                              archive+clear the addressed comments when done
#
# The slug rule (/ -> %) and ~/.local/share/comments dir must match comments.lua.
set -euo pipefail

DIR="$HOME/.local/share/comments"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
slug="${root//\//%}"
f="$DIR/${slug}.jsonl"

case "${1:-read}" in
  read)
    echo "repo: $root"
    echo "queue: $f"
    if [ -s "$f" ]; then
      echo "--- comments ---"
      cat "$f"
    else
      echo "(no comments queued)"
    fi
    ;;
  clear)
    mkdir -p "$DIR/archive"
    ts="$(date +%Y%m%dT%H%M%S)"
    if [ -s "$f" ]; then
      cp "$f" "$DIR/archive/${slug}-${ts}.jsonl"
      : > "$f"
      echo "archived to $DIR/archive/${slug}-${ts}.jsonl and cleared the queue"
    else
      echo "(nothing to clear)"
    fi
    ;;
  path)
    echo "$f"
    ;;
  dispatch)
    # Auto-fire the /comments skill in a sibling agent pane. Every guard exits 0
    # silently: comments are often added outside herdr, and panes don't always
    # have an agent neighbor -- this must never surface an error into nvim.
    rel=""
    clear=""
    shift
    for a in "$@"; do
      case "$a" in
        --clear) clear=1 ;;
        *) rel="$a" ;;
      esac
    done
    [ -n "${HERDR_PANE_ID:-}" ] || exit 0
    command -v herdr >/dev/null 2>&1 || exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    # Same tab as this pane, not this pane, has a detected agent, and idle --
    # never interject into a working/blocked agent. First match wins.
    target="$(herdr pane list 2>/dev/null | jq -r --arg self "$HERDR_PANE_ID" '
      .result.panes as $p
      | ($p[] | select(.pane_id == $self) | .tab_id) as $tab
      | [ $p[] | select(.tab_id == $tab and .pane_id != $self
                        and .agent != null and .agent_status == "idle") ]
      | first // empty
      | "\(.pane_id)\t\(.agent)"' 2>/dev/null || true)"
    [ -n "$target" ] || exit 0
    pane="${target%%$'\t'*}"
    agent="${target##*$'\t'}"
    cmd="/comments${rel:+ $rel}${clear:+ --clear}"
    herdr pane run "$pane" "$cmd" >/dev/null 2>&1 || exit 0
    echo "$agent ($pane)"
    ;;
  *)
    echo "usage: comments.sh [read|clear|path|dispatch [rel] [--clear]]" >&2
    exit 2
    ;;
esac
