---
name: handoff-gb
description: Write a handoff doc for a Grok Bot conversation into ~/main/scratch and commit it on the main repo. Use when the user says "handoff-gb", "/handoff-gb", "write a grok handoff", or wants this chat captured before context is lost. Not the herdr handoff skill, and not handoff-and-close.
argument-hint: "[optional slug/topic for the filename]"
---

Capture this Grok Bot conversation as a standalone handoff doc in `~/main/scratch/`, then commit that file on the `main` repo. Someone with zero context should be able to read it and continue the work.

## The one hard rule

The filename **MUST** start with a date prefix `YYYY-MM-DD-`. No exceptions. Then a short kebab slug:

```
~/main/scratch/2026-06-21-<slug>.md
```

- Get the date from the environment (today, America/Chicago). Do not guess. If unsure, run `date +%F`.
- Slug = the topic argument if given, else derive a short one from the conversation.
- If that exact path already exists, append `-2`, `-3`, … rather than overwriting.
- `~/main/scratch/` is global. Write there regardless of which repo the work was in.

## Where the file lives

`~/main/scratch` is the scratch folder inside the `carsonjones/main` git repo. The handoff is not done until that one file is committed on `main`'s default branch.

Prefer the checkout on the user's Mac (`~/main`) when that machine is connected. If it is asleep or disconnected, use a checkout of `carsonjones/main` on this agent's computer instead.

Commit **only** the new handoff file. Do not stage other dirty files, do not amend, and do not force-push. If the Mac checkout has unrelated local changes, leave them alone and commit just this path.

Commit subject, matching the repo's short style:

```
handoff: <slug>
```

Push that commit. Print the file path and the commit URL. Keep the chat reply short. The document is the deliverable.

## Front matter (required)

```yaml
---
date: 2026-06-21
project: <repo name or path where the work happened>
branch: <git branch, if the work was in a repo>
topic: <one line>
status: <in-progress | done | blocked | exploring>
tags: [<a few>]
agent: grok-bot
---
```

Fill `project` and `branch` from the work directory when there is one. Omit `branch` if the work was not in a repo.

Do **not** add `session_id` or `resume`. This chat has no CLI resume command, and herdr pane ids do not apply. Never invent an id.

## Body

Write it for a reader who wasn't here. Aim for a tight, skimmable doc, not a transcript. Include, in roughly this order, whatever applies:

- **Goal.** What we set out to do, in one or two lines.
- **State / outcome.** What's done, what works, what's left. Be honest about failures and dead ends.
- **Key decisions.** What we chose and why, including options rejected.
- **Code touchpoints.** Files the next person needs.
- **Next steps.** Concrete and actionable.
- **Open questions.** Anything unresolved.

## Always show sources

This is mandatory, not optional:

- **Links and attribution.** Any URL, repo, issue, doc, or person referenced in the conversation goes in a `## Sources` section with a real link.
- **Data analysis.** If the work involved querying data, include the actual queries used in fenced code blocks, plus where they ran. Paste the query. Don't paraphrase it.

## After writing

Print the full path of the file and the commit URL. Keep the chat reply short.
