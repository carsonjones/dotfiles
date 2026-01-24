#!/usr/bin/env bash
# Clean dev tool caches. Safe for running services (they use compiled binaries).
set -u

human() { df -h / | awk 'NR==2 {print "  / used: "$3" / "$2" ("$5")"}'; }
step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
run()   { echo "  \$ $*"; "$@" || echo "  (skipped/failed)"; }

step "Before"; human

step "Go caches"
if command -v go >/dev/null; then
  run go clean -modcache
  run go clean -cache
  run go clean -fuzzcache
fi

step "Bun cache"
rm -rf ~/.bun/install/cache 2>/dev/null && echo "  cleared ~/.bun/install/cache"

step "npm cache"
if command -v npm >/dev/null; then
  run npm cache clean --force
fi

step "pnpm / yarn caches (if present)"
command -v pnpm >/dev/null && run pnpm store prune
command -v yarn >/dev/null && run yarn cache clean

step "pip / uv caches"
command -v pip  >/dev/null && run pip cache purge
command -v uv   >/dev/null && run uv cache clean

step "cargo registry/git caches"
rm -rf ~/.cargo/registry/cache/* ~/.cargo/registry/src/* ~/.cargo/git/checkouts/* 2>/dev/null && echo "  cleared"

step "~/.cache"
run du -sh ~/.cache 2>/dev/null
rm -rf ~/.cache/* 2>/dev/null && echo "  cleared"

step "After"; human
