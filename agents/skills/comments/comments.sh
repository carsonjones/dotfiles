#!/usr/bin/env bash
# Helper for the /comments skill. Resolves the per-repo comment queue written by
# comments.nvim (<leader>hc) and reads or archives it.
#
#   comments.sh read           print the current repo's queued comments
#   comments.sh clear          archive the queue (recoverable) then truncate it
#   comments.sh clear --ids ID...
#                              archive, then drop ONLY those comment ids from the
#                              queue -- records appended since the agent read
#                              survive. This is the safe path the /comments skill
#                              uses so mid-work comments aren't lost.
#   comments.sh path           print the queue file path
#   comments.sh dispatch [rel] [--clear]
#                              hand "/comments [rel] [--clear]" to a sibling agent
#                              in the same herdr tab. Prefers an idle agent; if
#                              every agent is busy, spawns a new pane below one,
#                              boots claude, and sends there. Silent no-op if not
#                              in herdr / no agent neighbor. --clear asks the
#                              receiving agent to archive+clear the ids it read.
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
    if [ "${2:-}" = "--ids" ]; then
      # Smart clear: drop ONLY the given ids, keep everything else (comments
      # appended while the agent worked, other files, deferred notes).
      shift 2
      [ "$#" -gt 0 ] || { echo "clear --ids: no ids given" >&2; exit 2; }
      [ -s "$f" ] || { echo "(nothing to clear)"; exit 0; }
      command -v jq >/dev/null 2>&1 || { echo "clear --ids needs jq" >&2; exit 2; }
      ids_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
      cp "$f" "$DIR/archive/${slug}-${ts}.jsonl"
      tmp="$(mktemp)"
      # keep records whose id is NOT in the cleared set; drop malformed lines
      jq -c --argjson ids "$ids_json" 'select((.id as $i | $ids | index($i)) | not)' \
        "$f" > "$tmp" 2>/dev/null || true
      mv "$tmp" "$f"
      echo "archived to $DIR/archive/${slug}-${ts}.jsonl and cleared ${#} id(s)"
    elif [ -s "$f" ]; then
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
    cmd="/comments${rel:+ $rel}${clear:+ --clear}"

    panes="$(herdr pane list 2>/dev/null || true)"
    [ -n "$panes" ] || exit 0

    # Prefer an idle agent in this tab -- cheap, reuses a warm session.
    idle="$(printf '%s' "$panes" | jq -r --arg self "$HERDR_PANE_ID" '
      .result.panes as $p
      | ($p[] | select(.pane_id == $self) | .tab_id) as $tab
      | [ $p[] | select(.tab_id == $tab and .pane_id != $self
                        and .agent != null and .agent_status == "idle") ]
      | first // empty
      | "\(.pane_id)\t\(.agent)"' 2>/dev/null || true)"
    if [ -n "$idle" ]; then
      pane="${idle%%$'\t'*}"
      agent="${idle##*$'\t'}"
      herdr pane run "$pane" "$cmd" >/dev/null 2>&1 || exit 0
      echo "$agent ($pane)"
      exit 0
    fi

    # No idle agent. If a busy agent is in this tab, spawn a fresh pane below it
    # and boot claude there so the comments still get worked -- instead of the
    # old silent drop that stranded them in the queue.
    busy="$(printf '%s' "$panes" | jq -r --arg self "$HERDR_PANE_ID" '
      .result.panes as $p
      | ($p[] | select(.pane_id == $self) | .tab_id) as $tab
      | [ $p[] | select(.tab_id == $tab and .pane_id != $self
                        and .agent != null
                        and (.agent_status == "working" or .agent_status == "blocked")) ]
      | first // empty
      | "\(.pane_id)\t\(.cwd)"' 2>/dev/null || true)"
    [ -n "$busy" ] || exit 0
    busy_pane="${busy%%$'\t'*}"
    busy_cwd="${busy##*$'\t'}"

    # Self-expiring spawn lock: a burst of comments must not spawn a fleet while
    # the first claude is still cold-booting (its status reads unknown, not idle).
    # One spawned agent drains the WHOLE queue at start, so one spawn covers the
    # burst. Lock is a single fixed file per repo; staleness judged by timestamp
    # (TTL below), so an abandoned lock never permanently blocks -- no reaper.
    lock="$DIR/.dispatch-${slug}.lock"
    ttl=45
    now="$(date +%s)"
    if [ -f "$lock" ]; then
      prev="$(cat "$lock" 2>/dev/null || echo 0)"
      case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
      if [ "$((now - prev))" -lt "$ttl" ]; then
        exit 0  # recent spawn in flight -- it'll drain the queue
      fi
    fi
    mkdir -p "$DIR"
    echo "$now" > "$lock"

    new="$(herdr pane split "$busy_pane" --direction down --cwd "$busy_cwd" --no-focus 2>/dev/null \
      | jq -r '.result.pane.pane_id // empty' 2>/dev/null || true)"
    [ -n "$new" ] || exit 0
    herdr pane run "$new" "claude --dangerously-skip-permissions \"$cmd\"" >/dev/null 2>&1 || exit 0
    echo "spawned claude ($new, below busy $busy_pane)"
    ;;
  *)
    echo "usage: comments.sh [read|clear [--ids ID...]|path|dispatch [rel] [--clear]]" >&2
    exit 2
    ;;
esac
