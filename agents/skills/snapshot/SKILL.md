---
name: snapshot
description: Summarize the latest working-tree changes, then stage and commit everything in one shot. Use when the user says "/snapshot", "snapshot this", "commit everything", or wants a quick checkpoint of all current changes.
argument-hint: "[optional commit message override]"
---

Quick checkpoint: summarize what changed, then stage + commit **all** changes (tracked, untracked, deletions) in one commit.

## Steps

1. Survey the changes. Run in parallel:
   - `git status --short`
   - `git diff --stat HEAD`
   - `git diff` (and note untracked file contents if relevant)
2. Write a short summary of what changed — group by theme, not file-by-file. Keep it tight.
3. Stage everything: `git add -A`
4. Commit with a concise message:
   - If `$ARGUMENTS` is given, use it as the commit message.
   - Else derive a one-line message from the summary (concise, sacrifice grammar for concision — see global CLAUDE.md).
   - End the commit message with the Co-Authored-By trailer.

## Rules

- One commit, everything in it. No interactive staging, no splitting.
- If the tree is clean (`git status --short` empty), say so and stop — nothing to commit.
- If on the default branch (`main`), that's fine here — this is a checkpoint flow, commit in place. Do **not** branch or push unless asked.
- Don't push. Snapshot = local commit only.
- Show the user the summary and the final `git log -1 --oneline` after committing.

## Commit message shape

```
<one-line summary>

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

Keep the subject under ~60 chars when you can.
