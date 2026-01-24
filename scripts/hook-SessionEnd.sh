#!/bin/bash
# Runs when a session ends. Appends one line to memory/sessions.md so past
# sessions are greppable without scanning ~800MB of transcripts.
# Hook JSON (session_id, transcript_path, cwd, reason) arrives on stdin.
#
# This file and find-session.ts are symlinks into ~/src/dotfiles. bash dirname
# does NOT resolve symlinks, so DIR stays the workspace -- but bun's
# import.meta.dir DOES, so the index path is passed explicitly.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$DIR/scripts/hook-errors.log"

# stdout is dropped (hook output would land in context), stderr goes to LOG.
if ! ERR=$(bun run "$DIR/scripts/find-session.ts" --append-index \
  --index "$DIR/memory/sessions.md" 2>&1 >/dev/null); then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] find-session --append-index failed: $ERR" >>"$LOG"
fi
