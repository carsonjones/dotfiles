#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Pull inline review notes from a live Hunk session into the comments.nvim queue.

Hunk (https://hunk.dev) is a terminal diff viewer. While reviewing a diff you can
leave inline notes with `c`; this drains those human notes out of the ephemeral
session and appends them to the same per-repo JSONL queue comments.nvim writes,
so the `/comments` skill consumes nvim and Hunk notes through one path.

  hunk-sync.py [pull]     import live Hunk user notes into this repo's queue
  hunk-sync.py watch      drain this repo's live notes on an interval until killed
  hunk-sync.py --dry-run  show what would be imported without writing
  hunk-sync.py path       print this repo's queue file path

Non-destructive: notes are copied, not removed from the session. Re-runs are
idempotent -- each imported record carries the source note id and is skipped if
already present (or, lacking an id, deduped on file+line+body).

Queue location + slug rule (/ -> %) match comments.lua / comments.sh / comments.py.
Stdlib only; runs via `uv run` (or any python3). Requires the `hunk` CLI on PATH.
"""

from __future__ import annotations

import datetime as _dt
import json
import random
import subprocess
import sys
import time
from pathlib import Path

DIR = Path.home() / ".local" / "share" / "comments"

HELP = """\
hunk-sync — pull live Hunk inline notes into the comments.nvim queue

usage:
  hunk-sync [pull]       import this repo's live Hunk user notes into the queue (default)
  hunk-sync watch        drain this repo's notes every --interval secs until killed
  hunk-sync --dry-run    preview the mapping; write nothing
  hunk-sync --type <t>   source note type: user (default), agent, ai, all
  hunk-sync --interval N poll seconds for `watch` (default 2)
  hunk-sync path         print this repo's queue file path
  hunk-sync -h, --help   show this help

non-destructive and idempotent: notes are copied (not removed from Hunk) and
re-runs skip notes already imported. queue lives under ~/.local/share/comments
(slug rule / -> %), read by the /comments skill. needs the `hunk` CLI on PATH.\
"""

# Field-name fallbacks — Hunk's `comment list --json` shape is tolerated loosely
# so a schema tweak upstream doesn't silently drop notes.
_FILE_KEYS = ("filePath", "file", "path", "rel")
_NEWRANGE_KEYS = ("newRange", "new_range")
_OLDRANGE_KEYS = ("oldRange", "old_range")
_NEWLINE_KEYS = ("newLine", "new_line")
_OLDLINE_KEYS = ("oldLine", "old_line")
_LINE_KEYS = ("line", "lineNumber")
_BODY_KEYS = ("body", "summary", "text", "comment")
_ID_KEYS = ("noteId", "id", "commentId")
_TS_KEYS = ("ts", "createdAt", "created_at", "timestamp")


def repo_root() -> str:
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True,
    )
    root = out.stdout.strip()
    return root if out.returncode == 0 and root else str(Path.cwd())


def slug_of(root: str) -> str:
    return root.replace("/", "%")


def queue_path(root: str) -> Path:
    return DIR / f"{slug_of(root)}.jsonl"


def load(f: Path) -> list[dict]:
    if not f.exists():
        return []
    records = []
    for line in f.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return records


def random_id() -> str:
    charset = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return "".join(random.choice(charset) for _ in range(6))


def _first(d: dict, keys: tuple[str, ...]):
    for k in keys:
        if k in d and d[k] not in (None, ""):
            return d[k]
    return None


def fetch_notes(root: str, note_type: str) -> list[dict] | None:
    """Run `hunk session comment list` for this repo and normalize to a list.
    Returns None when there is no live session for this repo (benign)."""
    cmd = ["hunk", "session", "comment", "list",
           "--repo", root, "--type", note_type, "--json"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError:
        print("hunk CLI not found on PATH", file=sys.stderr)
        raise SystemExit(1)
    if out.returncode != 0:
        return None  # no live session for this repo
    try:
        data = json.loads(out.stdout or "null")
    except json.JSONDecodeError:
        print("could not parse Hunk JSON output", file=sys.stderr)
        raise SystemExit(1)
    if data is None:
        return []
    if isinstance(data, list):
        return data
    # Object wrapper: {"comments":[...]} / {"notes":[...]} / first list value.
    for key in ("comments", "notes", "items"):
        if isinstance(data.get(key), list):
            return data[key]
    for v in data.values():
        if isinstance(v, list):
            return v
    return []


def _lines(note: dict) -> tuple[int, int] | None:
    """Resolve (line, end_line), 1-based. Prefers a [start, end] range on the
    new side, then old side, then any scalar line key."""
    rng = _first(note, _NEWRANGE_KEYS) or _first(note, _OLDRANGE_KEYS)
    if isinstance(rng, (list, tuple)) and rng:
        try:
            start = int(rng[0])
            end = int(rng[-1])
        except (TypeError, ValueError):
            return None
        return (start, end) if start <= end else (end, start)
    scalar = _first(note, _NEWLINE_KEYS) or _first(note, _OLDLINE_KEYS) or _first(note, _LINE_KEYS)
    if scalar is None:
        return None
    try:
        n = int(scalar)
    except (TypeError, ValueError):
        return None
    return (n, n)


def to_record(note: dict, root: str) -> dict | None:
    """Map a Hunk note onto a comments.nvim queue record. None if unmappable."""
    raw_file = _first(note, _FILE_KEYS)
    lines = _lines(note)
    body = _first(note, _BODY_KEYS)
    if raw_file is None or lines is None or body is None:
        return None
    line, end_line = lines

    # Resolve absolute + repo-relative paths (Hunk paths are repo-relative).
    p = Path(raw_file)
    abspath = str(p) if p.is_absolute() else str(Path(root) / raw_file)
    rel = abspath[len(root) + 1:] if abspath.startswith(root + "/") else raw_file

    rationale = _first(note, ("rationale",))
    if rationale:
        body = f"{body}\n\n{rationale}"

    ts = _first(note, _TS_KEYS)
    if isinstance(ts, str):
        # Normalize to comments.lua's local ISO (no zone/millis).
        try:
            ts = _dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%dT%H:%M:%S")
        except ValueError:
            ts = None
    if not ts:
        ts = _dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

    return {
        "id": random_id(),
        "path": abspath,
        "rel": rel,
        "repo": root,
        "line": line,
        "end_line": end_line,
        "body": body,
        "ts": ts,
        "hunk_id": _first(note, _ID_KEYS),      # provenance + dedup key
        "author": _first(note, ("author",)),
        "source": "hunk",
    }


def dedup_key(rec: dict):
    hid = rec.get("hunk_id")
    if hid:
        return ("hid", hid)
    return ("plb", rec.get("path"), rec.get("line"), (rec.get("body") or "").strip())


def _collect_new(root: str, note_type: str) -> tuple[list[dict], int, int] | None:
    """Fresh (not-yet-queued) records for this repo, plus mapped/unmapped counts.
    None when no live session exists."""
    notes = fetch_notes(root, note_type)
    if notes is None:
        return None
    mapped = [r for r in (to_record(n, root) for n in notes) if r]
    unmapped = len(notes) - len(mapped)
    existing = {dedup_key(r) for r in load(queue_path(root))}
    fresh = [r for r in mapped if dedup_key(r) not in existing]
    return fresh, len(mapped), unmapped


def _append(root: str, fresh: list[dict]) -> None:
    DIR.mkdir(parents=True, exist_ok=True)
    with queue_path(root).open("a") as f:
        for r in fresh:
            f.write(json.dumps(r) + "\n")


def cmd_pull(note_type: str, dry_run: bool) -> int:
    root = repo_root()
    collected = _collect_new(root, note_type)
    if collected is None:
        print("no live Hunk session for this repo", file=sys.stderr)
        return 0
    fresh, mapped, unmapped = collected

    if unmapped:
        print(f"skipped {unmapped} note(s) with no file/line/body Hunk could give",
              file=sys.stderr)
    if not fresh:
        print(f"nothing new to import ({mapped} note(s) already in the queue)")
        return 0

    qpath = queue_path(root)
    if dry_run:
        print(f"would import {len(fresh)} note(s) into {qpath}:\n")
        for r in fresh:
            print(f"  {r['rel']}:{r['line']}  {(r['body'] or '').splitlines()[0]}")
        return 0

    _append(root, fresh)
    print(f"imported {len(fresh)} Hunk note(s) into {qpath}")
    print("run /comments (or `comments.py list`) to work through them")
    return 0


def cmd_watch(note_type: str, interval: float) -> int:
    """Drain this repo's live notes every `interval` secs until interrupted.
    Meant to run alongside a Hunk session (notes are memory-only, so continuous
    draining is what survives closing the TUI)."""
    root = repo_root()
    print(f"watching Hunk notes for {root} every {interval}s (ctrl-c to stop)",
          file=sys.stderr)
    total = 0
    try:
        while True:
            collected = _collect_new(root, note_type)
            if collected:
                fresh, _mapped, _unmapped = collected
                if fresh:
                    _append(root, fresh)
                    total += len(fresh)
                    print(f"+{len(fresh)} note(s) -> queue ({total} total)",
                          file=sys.stderr)
            time.sleep(interval)
    except KeyboardInterrupt:
        print(f"\nstopped; imported {total} note(s) this run", file=sys.stderr)
    return 0


def main(argv: list[str]) -> int:
    note_type = "user"
    dry_run = False
    interval = 2.0
    rest = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help", "help"):
            print(HELP)
            return 0
        if a == "--dry-run":
            dry_run = True
        elif a == "--type":
            i += 1
            if i >= len(argv):
                print("--type needs a value (user|agent|ai|all)", file=sys.stderr)
                return 2
            note_type = argv[i]
        elif a == "--interval":
            i += 1
            try:
                interval = float(argv[i])
            except (IndexError, ValueError):
                print("--interval needs a number of seconds", file=sys.stderr)
                return 2
        else:
            rest.append(a)
        i += 1

    cmd = rest[0] if rest else "pull"
    if cmd == "path":
        print(queue_path(repo_root()))
        return 0
    if cmd == "pull":
        return cmd_pull(note_type, dry_run)
    if cmd == "watch":
        return cmd_watch(note_type, interval)
    print(f"unknown command: {cmd}\n", file=sys.stderr)
    print(HELP, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
