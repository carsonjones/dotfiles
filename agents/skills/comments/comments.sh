#!/usr/bin/env bash
# Helper for the /comments skill. Resolves the per-repo comment queue written by
# comments.nvim (<leader>hc) and reads or archives it.
#
#   comments.sh read    print the current repo's queued comments
#   comments.sh clear   archive the queue (recoverable) then truncate it
#   comments.sh path     print the queue file path
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
  *)
    echo "usage: comments.sh [read|clear|path]" >&2
    exit 2
    ;;
esac
