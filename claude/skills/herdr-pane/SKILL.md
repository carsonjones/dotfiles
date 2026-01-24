---
name: herdr-pane
description: Move the current terminal pane to another herdr tab/workspace (or split, swap, zoom, rename it) using the herdr CLI. Use when the user says "/herdr-pane", "move this pane to the X tab", "move this terminal to X", "send this pane to a new tab", "split off this pane", or otherwise wants to relocate/reorganize the pane the agent is running in. Resolves the current pane and the target tab by label, then moves.
argument-hint: "[target tab label, e.g. 'repayments' | 'new tab']"
---

# herdr-pane — relocate the current terminal pane

`herdr` is the terminal workspace manager this agent runs inside. Each agent runs in a **pane**, panes live in **tabs**, tabs live in a **workspace**. This skill moves the *current* pane (the one this agent is in) to another tab — the common ask being "move this pane to the `<X>` tab".

All `herdr` subcommands emit **JSON** on stdout. Parse it; don't eyeball.

## Workflow

### 1. Identify the current pane

```bash
herdr pane current --current
```

Grab `result.pane.pane_id` (e.g. `w…:p1Y`), and note `tab_id` / `workspace_id` for context. `--current` targets the pane the command runs in — exactly the one this agent occupies.

### 2. Resolve the target tab

```bash
herdr tab list
```

Match the user's requested label against each tab's `label` (case-insensitive, fuzzy is fine — `"repayments"` → the tab labelled `repayments`). Capture its `tab_id`.

- **Multiple matches / no match:** list the available tab labels back to the user and ask which one. Do **not** guess into the wrong tab.
- **User wants a brand-new tab:** skip this step and use `--new-tab` in step 3.

### 3. Move

Into an existing tab (splits alongside whatever pane is already there):

```bash
herdr pane move <pane_id> --tab <tab_id> --split right --focus
```

- `--split right|down` — orientation of the split in the destination. Default to `right`; use `down` if the user asks or the destination is wide/short.
- `--ratio 0.5` — optional split ratio.
- `--target-pane <id>` — split next to a specific pane in the destination (default: the tab's focused pane).
- `--focus` / `--no-focus` — whether to follow the pane to its new home. Default `--focus` so the user lands where the work is.

Into a brand-new tab or workspace:

```bash
herdr pane move <pane_id> --new-tab --label "<text>" --focus
herdr pane move <pane_id> --new-workspace --label "<ws>" --tab-label "<tab>" --focus
```

### 4. Confirm

The move returns `move_result.changed: true` plus `previous_tab_id` and the new `tab_id`. Report the source→destination tab labels in one line. Done — stop.

## Related pane ops (same CLI, when asked)

- `herdr pane split [--pane ID|--current] --direction right|down [--ratio F] [--cwd PATH] [--focus]` — split the current pane in place.
- `herdr pane swap --direction left|right|up|down --current` — swap with a neighbor.
- `herdr pane swap --source-pane ID --target-pane ID` — swap two specific panes.
- `herdr pane zoom --current --toggle` — (un)maximize.
- `herdr pane rename <pane_id> <label>` (or `--clear`) — label a pane.
- `herdr pane focus --direction … --current` — move keyboard focus without moving the pane.
- `herdr tab focus <tab_id>` / `herdr tab create [--label TEXT] [--cwd PATH]` / `herdr tab rename <tab_id> <label>`.

## Notes

- Discover usage live with `herdr pane --help` and `herdr tab --help` — the surface above is the stable core but flags can grow.
- Never `herdr pane close` the current pane to "move" it — that kills the agent. Always use `pane move`.
- `pane move` is non-destructive: it relocates, preserving the running process/agent session.
