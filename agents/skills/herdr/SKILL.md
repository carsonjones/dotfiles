---
name: herdr
description: Drive other herdr panes/agents in the session — list them, figure out which is which, and send text/keys. Use when the user mentions a "pane", "agent", or "session", or says "/herdr", "send X to the other pane", "tell the other claude/agent to ...", "run X in pane Y", "what's in the other session", or wants to inspect or control a neighbor pane/agent.
argument-hint: "[what to send and where]"
---

Control other panes in the herdr session via the `herdr pane` CLI. Keep it simple: **list → identify → send**.

## 1. Get panes

```sh
herdr pane list
```

JSON. Each pane has:
- `pane_id` — e.g. `w4:pX` (the target you send to)
- `focused: true` — that's **you**, skip it
- `agent` / `agent_status` — `claude` + `idle|working|blocked` = a Claude pane; absent/`unknown` = a plain shell
- `cwd` — helps tell panes apart

`herdr pane current` = just the focused (you) pane.

## 2. Name them

No real "names" — identify panes by `agent` + `cwd` + `agent_status`. Tell the user what you found before sending, e.g. "pA = other Claude (idle), pY = shell". If ambiguous, `herdr pane read <id>` shows recent output to disambiguate. Don't guess — confirm the target.

## 3. Send keys

```sh
herdr pane send-text <pane_id> "the text"     # types it, no newline
herdr pane send-keys <pane_id> enter          # submits it
herdr pane run      <pane_id> "<cmd>"          # text + enter in one shot
```

- **send-text alone leaves it unsubmitted** at the prompt — safe default when unsure.
- Add `send-keys <id> enter` to actually submit (to a Claude pane) or run (in a shell).
- Other keys: `enter`, `ctrl-c`, etc.
- Empty output = success. Verify with `herdr pane read <id> --source recent --lines 30`.

## Safety

- Never `enter` into a **shell** pane unless the user clearly wants the command run.
- Re-read `herdr pane list` if pane ids might have changed — they're not stable across layout changes.
