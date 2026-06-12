---
name: comments
description: Address the review comments you left in nvim while reviewing files. Reads the per-repo comment queue written by the comments.nvim plugin (<leader>hc), works through each note (clarifying where needed), then archives the queue for a fresh slate when told. Use when the user says "/comments", "check the comments", "address my review notes", or "go through the comments for this file".
---

# Comments

While reviewing files in nvim, the user presses `<leader>hc` to leave inline review
comments — questions to answer, changes to make, things to weigh. Each comment is appended
to a per-repo JSONL queue. This skill reads that queue, works through the notes with the
user, and archives it when done.

This is decoupled from any diff viewer: comments can land on **any line of any file** —
committed, unchanged, or untracked. You just read the queue file.

## Workflow

### 1. Read the queue

The plugin writes one JSONL file per repo at `~/.local/share/comments/<slug>.jsonl` (slug =
repo root with `/` → `%`). Read this repo's queue with the bundled helper:

```bash
bash ~/.claude/skills/comments/comments.sh read
```

Each line is a JSON record:

| field | meaning |
|---|---|
| `id` | short unique id |
| `path` | absolute file path |
| `rel` | repo-relative path (use this to group/display) |
| `repo` | repo root |
| `line` / `end_line` | 1-based line range the comment anchors to (equal for a single line) |
| `body` | the comment text |
| `ts` | when it was written |

- If the queue is empty or missing → tell the user there are no comments to address and stop.
- If the user scoped the request to a file ("comments for this file", or a path in
  `$ARGUMENTS`) → only act on records whose `rel`/`path` matches.

### 2. Address each comment

Work through them grouped by file, top to bottom. For each:

1. Read the targeted file around `line`–`end_line` so you see what the user saw.
2. Read the `body` and classify the intent yourself:
   - **a question** → answer it
   - **a change request** → make the edit
   - **a suggestion to weigh** → evaluate, then recommend
3. **Clarify before acting when the ask is ambiguous or underspecified** — don't guess at a
   change the user didn't clearly request. Ask a focused question, then proceed.
4. Make the edit (or answer) and note what you did, referencing `rel:line`.

Batch related edits, but keep the user in the loop on anything non-obvious or hard to
reverse. When done, give a short summary: what you changed, what you answered, and anything
you deferred or still need.

### 3. Archive for a fresh slate — only when told

Do **not** clear the queue automatically. After the user confirms the work is done and asks
to clear / reset / "fresh slate", archive the file (recoverable) then truncate it:

```bash
bash ~/.claude/skills/comments/comments.sh clear
```

If the user only wants to clear comments for one file, don't run `clear` (it wipes the whole
queue). Instead archive a copy, then rewrite the file keeping only records whose `rel`
doesn't match the cleared file (e.g. with `jq`).

## Notes

- The plugin and this skill must agree on the slug rule (`/` → `%`) and the
  `~/.local/share/comments` directory. The capture side lives in
  `~/src/dotfiles/nvim/lua/comments.lua`.
- Records are append-only; the same line may have multiple comments. Address them all.
