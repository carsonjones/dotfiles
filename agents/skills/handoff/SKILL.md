---
name: handoff
description: Write a handoff doc capturing the current conversation into ~/main/scratch so the work can be picked up later (by you, future-you, or another agent). Use when the user says "/handoff", "write a handoff", "save this conversation", "dump this to scratch", or wants the session captured before context is lost. Works in any repo.
argument-hint: "[optional slug/topic for the filename]"
---

Capture the current conversation as a standalone handoff doc in `~/main/scratch/`. Someone with zero context should be able to read it and continue the work.

## The one hard rule

The filename **MUST** start with a date prefix `YYYY-MM-DD-`. No exceptions. Then a short kebab slug:

```
~/main/scratch/2026-06-21-<slug>.md
```

- Get the date from the environment (today). Do not guess — if unsure, run `date +%F`.
- Slug = the `$ARGUMENTS` topic if given, else derive a short one from the conversation (e.g. `nvim-lsp-rename`, `herdr-theme-api`).
- If that exact path already exists, append `-2`, `-3`, … rather than overwriting.
- `~/main/scratch/` is global — write there regardless of which repo we're in.

## Front matter (required)

```yaml
---
date: 2026-06-21
project: <repo name or path where this was initiated, e.g. ~/src/dotfiles>
branch: <git branch, if in a repo>
topic: <one line>
status: <in-progress | done | blocked | exploring>
tags: [<a few>]
agent: <claude | codex | ..., if resolved>
session_id: <id, if resolved>
resume: <command to resume this session, if resolved>
---
```

Fill `project`/`branch` from the cwd: `basename $(git rev-parse --show-toplevel)` and `git branch --show-current` (omit branch if not in a repo).

### Session keys

Resolve the agent + session id so the next reader can drop back into *this* conversation, not just read about it:

```bash
herdr pane current --current | python3 -c 'import json,sys; s=json.load(sys.stdin)["result"]["pane"].get("agent_session") or {}; print(s.get("agent",""), s.get("value",""))'
```

`herdr` is the terminal workspace manager the agent runs inside; it learns the id from its agent-integration hook, so this covers claude, codex, cursor, and friends. If herdr isn't running or the pane reports no `agent_session`, fall back to `$CLAUDE_CODE_SESSION_ID`. If neither resolves, **omit all three keys** — never invent an id.

`resume` command by agent:

- `claude` -> `claude --resume <id>`
- `codex` -> `codex resume <id>`
- anything else -> use that CLI's resume flag if you know it, otherwise keep `session_id` and drop `resume`

Resume runs from the `project` dir, so mention that in the doc if it isn't obvious.

## Body

Write it for a reader who wasn't here. Aim for a tight, skimmable doc — not a transcript. Include, in roughly this order, whatever applies:

- **Goal** — what we set out to do, in one or two lines.
- **State / outcome** — what's done, what works, what's left. Be honest about failures and dead ends; a handoff that hides what broke is worse than none.
- **Key decisions** — what we chose and *why*, including options rejected.
- **Code touchpoints** — files + `path:line` refs the next person needs (these render clickable).
- **Next steps** — concrete, actionable.
- **Open questions** — anything unresolved.

## Always show sources

This is mandatory, not optional:

- **Links & attribution** — any URL, repo, issue, doc, or person referenced in the conversation goes in a `## Sources` section with a real link. If an idea came from someone (e.g. "Matt's skill"), name and link them.
- **Data analysis** — if the work involved querying data, include the **actual queries used** (SQL/bq/jq/etc.) in fenced code blocks, plus where they ran. Don't paraphrase a query — paste it so it's reproducible.

## After writing

Print the full path of the file you wrote so the user can open it. Keep your chat reply short — the document is the deliverable.
