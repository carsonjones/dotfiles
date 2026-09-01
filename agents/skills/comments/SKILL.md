---
name: comments
description: Address the review comments you left in nvim while reviewing files. Reads the per-repo comment queue written by the comments.nvim plugin (<leader>hc), works through each note (clarifying where needed), then archives the queue for a fresh slate when told. Use when the user says "/comments", "check the comments", "address my review notes", or "go through the comments for this file".
---

# Comments

While reviewing files in nvim, the user presses `<leader>hc` to leave inline review comments — questions to answer, changes to make, things to weigh. Each comment is appended to a per-repo JSONL queue. This skill reads that queue, works through the notes with the user, and archives it when done.

This is decoupled from any diff viewer: comments can land on **any line of any file** — committed, unchanged, or untracked. You just read the queue file.

Notes left inside a live [Hunk](https://hunk.dev) diff session (`c` in the TUI) can be pulled into this same queue first, so nvim and Hunk notes flow through one path — see `hunk-sync.py` under Notes.

## Workflow

### 1. Read the queue

The plugin writes one JSONL file per repo at `~/.local/share/comments/<slug>.jsonl` (slug = repo root with `/` → `%`). Read this repo's queue with the bundled helper:

```bash
bash ~/.agents/skills/comments/comments.sh read
```

If the user reviewed this changeset in Hunk and wants those notes too, drain the live session's inline notes into the queue first, then read as usual:

```bash
~/.agents/skills/comments/hunk-sync.py        # no-op if no live Hunk session
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
- If the user scoped the request to a file ("comments for this file", or a path in `$ARGUMENTS`) → only act on records whose `rel`/`path` matches.

### 2. Address each comment

Work through them grouped by file, top to bottom. For each:

1. Read the targeted file around `line`–`end_line` so you see what the user saw.
2. Read the `body` and classify the intent yourself:
   - **a question** → answer it
   - **a change request** → make the edit
   - **a suggestion to weigh** → evaluate, then recommend
3. **Clarify before acting when the ask is ambiguous or underspecified** — don't guess at a change the user didn't clearly request. Ask a focused question, then proceed.
4. Make the edit (or answer) and note what you did, referencing `rel:line`.

Batch related edits, but keep the user in the loop on anything non-obvious or hard to reverse. When done, give a short summary: what you changed, what you answered, and anything you deferred or still need.

### 3. Archive for a fresh slate — only when told

Do **not** clear the queue automatically — with one exception: `--clear` in `$ARGUMENTS` (the auto-dispatch pipeline passes it) is standing permission to archive+clear the comments you addressed, once you've finished addressing them. Clear **only the specific ids you read at the start of this run** — never a blanket wipe. Comments queued while you were working (a new dispatch may have spawned you mid-review, or the user kept commenting) must survive. Pass the exact ids to the smart-clear path:

```bash
bash ~/.agents/skills/comments/comments.sh clear --ids <id1> <id2> ...
```

This archives a recoverable copy, then drops only those ids from the queue, keeping every other record. Do **not** clear ids you deferred or left unresolved.

Otherwise (no `--clear` flag), wait until the user confirms the work is done and asks to clear / reset / "fresh slate". Prefer `clear --ids <the ids you addressed>` there too; use the blanket `clear` below only when the user explicitly wants the whole queue wiped:

```bash
bash ~/.agents/skills/comments/comments.sh clear
```

## Notes

- The plugin and this skill must agree on the slug rule (`/` → `%`) and the `~/.local/share/comments` directory. The capture side lives in `~/src/dotfiles/nvim/lua/comments.lua`.
- **Auto-dispatch**: comments queued from inside a herdr pane fire `comments.sh dispatch [rel]` (debounced), which hands the comments skill plus `[rel] [--clear]` to a sibling agent in the same herdr tab — invoked as `/comments` for a claude neighbor and `$comments` for a codex one, since the sigil differs per agent. It prefers an **idle** agent (reuses a warm session). If every agent in the tab is **working/blocked**, it spawns a fresh pane below the busy one, boots `claude --dangerously-skip-permissions "/comments …"`, and sends the comments there — so busy agents no longer strand comments in the queue. A self-expiring per-repo lock (`~/.local/share/comments/.dispatch-<slug>.lock`, 45s TTL) stops a burst of comments from spawning a fleet while the first spawned claude is still cold-booting; the one spawned agent drains the whole queue at start. Both capture paths dispatch: nvim `<leader>hc` (comments.lua) and the `hunk()` zsh wrapper (`hunk-sync.py watch/pull --dispatch`). So this skill may be invoked without the user typing anything — treat it like a normal `/comments` run scoped to `$ARGUMENTS`. Not-in-herdr or no agent neighbor still no-ops silently. Agent-invoked `hunk-sync.py pull` must **not** pass `--dispatch` — that flag is for the user-side wrapper only.
- Records are append-only; the same line may have multiple comments. Address them all.
- `comments.py` is a standalone CLI for the user (run via `uv run`): `list` shows every queued comment across **all** repos, `rm <id>...` removes records by id (archiving the touched queue first), and bare `rm` opens an interactive picker. Separate from this skill's automated flow.
- `hunk-sync.py` pulls inline notes from a live Hunk session (`hunk session comment list`) into this repo's queue. Non-destructive (notes stay in Hunk) and idempotent (re-runs skip already-imported notes via the source note id). `pull` imports once; `watch` drains on an interval until killed. `--dry-run` previews; `--type user|agent|ai|all` picks the source (default `user`). Records get `source: "hunk"` + `hunk_id` provenance fields, which the readers above ignore. Hunk keeps notes only in memory, so the `hunk()` zsh wrapper auto-runs `watch` during review sessions — nothing to remember.
