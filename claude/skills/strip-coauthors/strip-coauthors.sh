#!/usr/bin/env bash
#
# strip-coauthors — remove "Co-authored-by:" trailers from commits on the
# current branch that aren't yet on a base ref.
#
# Why this exists: Cursor cloud/background agents add a `Co-authored-by:` trailer
# to every commit, and (as of 2026) there is NO setting to disable it for cloud
# agents — the IDE toggle under Settings > Agents > Attribution only covers
# in-IDE commits. So the only no-org-buy-in fix is a post-hoc cleanup. This is it.
#
# Safe by default: dry-run unless --apply, saves a backup ref before rewriting,
# and never pushes for you (history rewrite on a shared branch is your call).
#
# Usage:
#   strip-coauthors.sh [--base <ref>] [--pattern <text>] [--apply]
#
#   --base <ref>      Scan <ref>..HEAD. Default: origin/main
#   --pattern <text>  Case-insensitive line prefix to strip. Default: Co-authored-by:
#   --apply           Actually rewrite (a backup ref is saved first).
#   -h, --help        This help.
#
# After --apply:  review with `git log <base>..HEAD`, then push yourself with
#                 `git push --force-with-lease`. Undo with the printed backup ref.

set -euo pipefail

BASE="origin/main"
PATTERN="Co-authored-by:"
APPLY=0

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base)    BASE="${2:?--base needs a ref}"; shift 2 ;;
    --pattern) PATTERN="${2:?--pattern needs text}"; shift 2 ;;
    --apply)   APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not in a git repository." >&2; exit 1; }
git rev-parse --verify --quiet "$BASE" >/dev/null \
  || { echo "Base ref not found: $BASE" >&2; exit 1; }

RANGE="${BASE}..HEAD"

# Collect matching commits (portable — avoids bash-4 mapfile for macOS bash 3.2).
affected=""
count=0
while IFS= read -r h; do
  if git show -s --format='%B' "$h" | grep -qi "$PATTERN"; then
    affected="${affected}${h}
"
    count=$((count + 1))
  fi
done < <(git log "$RANGE" --format='%H')

if [ "$count" -eq 0 ]; then
  echo "No commits matching '$PATTERN' in $RANGE. Nothing to do."
  exit 0
fi

echo "Found $count commit(s) with '$PATTERN' in $RANGE:"
printf '%s' "$affected" | while IFS= read -r h; do
  [ -n "$h" ] && printf '  %.10s  %s\n' "$h" "$(git show -s --format='%s' "$h")"
done

if [ "$APPLY" -ne 1 ]; then
  echo
  echo "Dry run — nothing changed. Re-run with --apply to rewrite history."
  exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree has uncommitted changes — commit or stash first." >&2
  exit 1
fi

backup="refs/backup/strip-coauthors/$(date -u +%Y%m%dT%H%M%SZ)-$(git rev-parse --short HEAD)"
git update-ref "$backup" HEAD
echo "Backup ref saved: $backup -> $(git rev-parse --short HEAD)"

# Strip matching trailer lines, then drop any trailing blank lines they leave.
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f \
  --msg-filter "grep -vi '^[[:space:]]*${PATTERN}' | awk 'NF{last=NR} {buf[NR]=\$0} END{for(i=1;i<=last;i++) print buf[i]}'" \
  -- "$RANGE"

echo
echo "Done. Review:   git log --format='%h  %an  %s' $RANGE"
echo "Push:           git push --force-with-lease"
echo "Undo:           git reset --hard $backup"
