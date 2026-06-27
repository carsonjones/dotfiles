---
name: strip-coauthors
description: Remove "Co-authored-by:" trailers (e.g. the ones Cursor cloud/background agents auto-add) from commits on the current branch. Use when the user says "remove co-author", "strip co-authored-by", "clean the cursor co-author", "get rid of the co-author lines", or notices unwanted Co-authored-by trailers on recent commits.
argument-hint: "[--base <ref>] (default origin/main)"
---

Remove `Co-authored-by:` trailers from commits on the current branch. The common case is cleaning up after **Cursor cloud/background agents**, which add a `Co-authored-by: <name> <…@gmail.com>` line to every commit. As of 2026 there is **no setting to disable this for cloud agents** — the IDE toggle (Settings → Agents → Attribution) only affects in-IDE commits — so post-hoc cleanup is the only fix that doesn't require repo-wide / org changes.

## How to run

The bundled script is the source of truth. It is **dry-run by default**, saves a **backup ref** before rewriting, and **never pushes** (history rewrite on a shared branch is the user's call).

```bash
bash "$(dirname "$0")/strip-coauthors.sh"            # dry run: list affected commits
bash "$(dirname "$0")/strip-coauthors.sh" --apply    # rewrite (backup ref saved)
```

Resolve the script path relative to this SKILL.md (it sits beside it). Run the **dry run first**, show the user which commits would change, then run `--apply` only after they confirm.

Options: `--base <ref>` (range is `<ref>..HEAD`, default `origin/main`), `--pattern <text>` (line prefix to strip, default `Co-authored-by:`).

## Critical safety rules

1. **Confirm the source branch state first.** `git fetch` and check `git rev-list --left-right --count HEAD...@{u}`. If the branch was rewritten upstream (e.g. a cloud agent rebased it), operate on the **remote tip**, not a stale local branch — `git reset --hard @{u}` (after backing up the old local ref) so local matches what you'll push.
2. **A cloud agent may still be active** on the branch (it pushed after you last did). Rewriting now will make the agent's *next* push diverge. Surface this and let the user decide whether the agent is done before pushing.
3. **Never push automatically.** After `--apply`, print the exact `git push --force-with-lease` command and let the user run it (or confirm explicitly first). `--force-with-lease` aborts rather than clobbering if the remote moved since the last fetch — do **not** `git fetch` right before the push, or you'll defeat the lease.
4. **Verify content is unchanged.** After rewriting, confirm the final tree is identical: `git diff <backup-ref> HEAD` should be empty (only commit metadata changed).
5. Leave the backup ref in place until the user confirms they're happy; then `git update-ref -d <backup-ref>` and `git update-ref -d` any `refs/original/*` that `filter-branch` created.

## Note on authorship

This strips only the `Co-authored-by:` *trailer*. It does **not** change the commit **author** (e.g. `Cursor Agent`) — that's intentional; the agent did make the commit. If the user also wants to re-author, that's a separate explicit ask.
