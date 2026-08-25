---
name: handoff-and-close
description: Write a handoff doc (same as /handoff), then quit this agent session and close the herdr pane it runs in. Use when the user says "/handoff-and-close", "handoff and close", "wrap up and kill this pane", "save this and shut it down", or otherwise wants the session captured *and* the terminal cleaned up. Terminal — nothing runs after this.
argument-hint: "[optional slug/topic for the filename]"
---

# handoff-and-close

`/handoff` + teardown. Write the doc, then exit the agent and close the pane so the tab isn't left holding a dead session.

This is destructive to the *session*, not the work: the handoff doc plus `resume` command in its front matter is how anyone (including future-you) gets back in.

## 1. Handoff first

Run the **`handoff`** skill and follow it exactly — filename rules, front matter, session keys, body, sources. `$ARGUMENTS` (if any) is the slug, pass it through.

Do **not** shortcut it. The doc is the only thing surviving this command.

## 2. Verify before arming teardown

Hard gate. Do not proceed unless:

- the file exists and is non-empty (`test -s <path>`)
- front matter has `session_id` + `resume` — or you've confirmed neither resolved (herdr not running / no `agent_session`)
- nothing is mid-flight: no uncommitted work the user expected you to finish, no background task still running, no unanswered question

If any of that fails: **stop, don't close.** Report what's missing and let the user decide.

## 3. Resolve pane + agent pid

```bash
herdr pane current --current      # -> result.pane.pane_id
herdr pane process-info --current # -> the `claude`/`codex` entry's pid in foreground_processes
```

Grab both. The pid is what tells the watcher the agent actually exited; the pane_id is what gets closed.

## 4. Say your last words

Print the handoff path and a one-line "closing this pane" note **before** arming teardown. Once the watcher fires the user won't see anything else — the pane is gone.

Keep it short:

```
~/main/scratch/2026-08-24-nvim-lsp-rename.md
resume: claude --resume 57c9408c-… (from ~/src/dotfiles)
closing this pane.
```

## 5. Arm the watcher, then let it exit you

You can't run a command after your own process dies, so detach one that waits for you:

```bash
nohup bash -c '
  pane="<pane_id>"; pid=<agent_pid>
  # let this turn finish before typing into our own pane
  for _ in $(seq 1 30); do
    herdr pane get "$pane" 2>/dev/null | grep -q "\"agent_status\":\"working\"" || break
    sleep 1
  done
  herdr pane run "$pane" "/exit" >/dev/null 2>&1   # graceful agent quit
  for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  herdr pane close "$pane" >/dev/null 2>&1          # then take the pane with it
' >/dev/null 2>&1 &
```

- `nohup` + full redirect: survives the agent exiting, returns immediately instead of blocking the tool call.
- Poll-then-send: typing `/exit` into a pane that's still `working` just queues it. Waiting for idle makes the quit clean.
- The `kill -0` loop gives the agent up to 60s to flush and exit on its own. If it hangs, `pane close` ends it anyway — the transcript is already on disk, so `--resume` still works.
- Hardcode the resolved `pane_id`/`pid` into the script. Don't re-resolve inside it; `--current` means *the watcher's* pane, which is not what you want.

Then stop. No further tool calls, no trailing summary — anything after this races the teardown.

## Notes

- Wrong pane is unrecoverable-ish: closing someone else's pane kills their work. Resolve with `--current`, never guess a `pane_id`.
- No herdr? (`herdr pane current` fails) — write the handoff, print the path, tell the user to close the pane themselves. Never `kill` the shell as a substitute.
- Related: `/handoff` (doc only, session stays alive), `/herdr-pane` (relocate the pane instead of ending it).
