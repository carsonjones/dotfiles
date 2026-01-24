---
name: herdr-worktree
description: Spin up an isolated git worktree in its own herdr workspace, launch a Claude agent there, and seed it with a written brief so it works a scoped change without polluting the current branch. Use when the user says "/herdr-worktree", "spin up a worktree for X", "kick off an isolated agent on X", "brief an agent to do X in a worktree", or wants an independent PR built off the side.
argument-hint: "[change to work + optional base/branch]"
---

Given a described change, create an isolated worktree, launch a briefed Claude agent in it, and hand back. Keeps independent PRs cleanly separated. Uses the `herdr` CLI (see the `herdr` skill for pane basics).

## Flow

1. **Recon in the current checkout first.** Before spinning anything up, grep/read enough to nail down: the real entry-point files, the mechanism, and the right **base branch**. Check whether the code the change depends on is on `main` (`git grep -l <symbol> main -- <path>`); if yes, base off `main` for a clean independent PR. The brief is only as good as this recon — capturing it here saves the agent from re-deriving it.

2. **Create the worktree** off the chosen base:
   ```sh
   herdr worktree create --workspace <cur_ws> --branch <branch> --base main \
     --label "<short-label>" --no-focus --json
   ```
   - `--workspace <cur_ws>`: your current workspace (`herdr pane current`, or `herdr worktree list --json` → `source_workspace_id`). Tells herdr which repo.
   - `--no-focus`: don't yank the user's view; opens in a new workspace (e.g. `w7`/`w8`).
   - Parse the JSON for `workspace.workspace_id` and `worktree.path`. Worktrees land at `~/.herdr/worktrees/<repo>/<branch-slug>`.

3. **Write the brief file** into the worktree root (NOT the repo you're in), with Write. Path: `<worktree.path>/<NAME>_BRIEF.md`. See "Brief anatomy".

4. **Launch the agent** rooted where the work happens (for dashboard work, the `product/dashboard` subdir, not the worktree root):
   ```sh
   herdr agent start <agent-name> --workspace <ws> \
     --cwd <worktree.path>/product/dashboard --no-focus -- claude
   herdr agent wait <agent-name> --status idle --timeout 60000
   ```

5. **Send + submit the seed prompt.** `agent send` writes text but does NOT submit — press enter separately:
   ```sh
   herdr agent send <agent-name> 'Read ./<NAME>_BRIEF.md at the worktree root (one level
   up from this dashboard cwd: ../../<NAME>_BRIEF.md) and follow it. Produce the written
   plan first and pause for my OK before large edits. Do not open a PR until I confirm.'
   herdr pane send-keys <pane_id> enter        # pane_id from agent start result, e.g. w8:p2
   ```
   Keep the prompt short and single-paragraph — multi-line sends can submit early in the TUI. Put all real detail in the brief FILE.

6. **Clear the first permission prompt.** A fresh agent asks to read the brief. Confirm, then approve session-wide reads:
   ```sh
   herdr agent read <agent-name> --source recent --lines 25   # confirm it's the read prompt
   herdr pane send-text <pane_id> "2"                          # "allow reading ... this session"
   herdr pane send-keys <pane_id> enter
   ```
   Only auto-approve read-only file access. Don't auto-approve writes/commands the user hasn't sanctioned.

7. **Hand back — don't babysit.** Tell the user the workspace id, worktree path, branch, and agent name, plus how to jump in:
   - `herdr agent focus <agent-name>` (or focus the workspace)
   - peek without switching: `herdr agent read <agent-name> --source recent --lines 40`

## Brief anatomy (the file the agent reads)

- **One-line framing**: "you're on an isolated worktree `<branch>` off `main` for X; keep the PR scoped."
- **Problem / motivation** in plain terms.
- **Entry points already traced** — exact `file:line` refs + what each does. Highest-value section; it's your step-1 recon.
- **What you still need to figure out** — open questions, with pointers to docs/dirs.
- **Deliverables** — numbered: (1) written plan first + PAUSE for OK, (2) implement, (3) tests, (4) validate (`pnpm lint --changed`, `pnpm typecheck`, relevant tests), (5) prepare a DRAFT PR per `docs/pull-request-guide.md`.
- **Guardrails**:
  - Do NOT `gh pr create` / `gs stack submit` until the user confirms.
  - Read relevant CLAUDE.md + domain docs before editing.
  - Match local file conventions.
  - Delete this brief file before committing.

## Parameters to derive

- `task_description` (free text) → drives recon + brief.
- `base` (default `main`).
- `branch` name (or derive from a slug).
- `cwd_subdir` (default `product/dashboard` for the dashboard repo; empty for others).
- `agent_name` / `label`.
- Auto-approve read-only perms (default yes); focus (default no).

## Opening the PR (when the user OKs)

The agent commits + shows the PR title/body but does NOT open until the user confirms. On go-ahead:

1. **Confirm scope is clean.** `git -C <worktree.path> status` and `git -C <worktree.path> diff main --stat`. Brief file deleted, only intended files changed.
2. **Drive it via the agent** (it holds the context):
   ```sh
   herdr agent send <agent-name> 'Looks good — open it as a DRAFT PR now.'
   herdr pane send-keys <pane_id> enter
   ```
   Approve the one-time `git push` / `gh` / `gs` prompts as they appear (`send-text <pane> "2"` + enter) — now user-sanctioned.
3. **Mechanics the agent runs** (git-spice repo; see `docs/git-spice.md`, `docs/pull-request-guide.md`):
   - Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
   - Push, then `gs branch submit --draft` or `gh pr create --draft --base main --title "type(scope): summary [LINEAR-ID]" --body-file <path>`.
   - PR body per the guide; end with the Claude Code generated-with line. **Always draft.**
4. **Capture the URL** back to the user via `herdr agent read <agent-name> --source recent`.

Prefer having the agent open the PR over doing it yourself — it holds the plan + diff. Don't merge; the draft is the end state. Stray `Co-authored-by` from another tool → `/strip-coauthors` (fetch + reset to remote tip first).

## Gotchas

- `agent send` = text only; always follow with `send-keys <pane> enter`.
- For dashboard tasks `--cwd` is the `product/dashboard` subdir; brief lives two levels up (`../../<NAME>_BRIEF.md`) — say so in the prompt.
- Worktree paths: `~/.herdr/worktrees/<repo>/<branch-with-slashes-as-dashes>`.
- Choose base deliberately: `main` for independent PR; current branch only if it genuinely stacks on unmerged work.
- Pane ids (`w8:p2`) come from the `agent start` JSON; re-list if layout changed.
- Fresh agents may warn "1 MCP server needs authentication" — harmless unless the task needs that server.
- Tell the agent to delete the brief before committing so it doesn't land in the PR.

## herdr subcommands used

`herdr worktree list|create|open|remove` · `herdr workspace list|create|focus|close` · `herdr agent start|wait|get|read|send|focus|rename` · `herdr pane list|current|send-text|send-keys|run|read`
