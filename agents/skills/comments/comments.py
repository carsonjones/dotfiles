#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Review and selectively remove comments queued by comments.nvim (<leader>hc).

Spans every per-repo queue under ~/.local/share/comments (slug rule: / -> %,
matching comments.lua / comments.sh).

  comments.py [list]        list every queued comment, grouped by repo
  comments.py rm <id>...    remove records by id (archives the touched queues first)
  comments.py rm            interactive picker (archives before removing)
  comments.py clear         archive then empty every queue, across all repos
  comments.py path          print the comments dir

Stdlib only; runs via `uv run` (or any python3).
"""

from __future__ import annotations

import datetime as _dt
import json
import shutil
import sys
from pathlib import Path

DIR = Path.home() / ".local" / "share" / "comments"
ARCHIVE = DIR / "archive"

HELP = """\
comments — review and selectively remove comments queued by comments.nvim (<leader>hc)

usage:
  comments [list]        list every queued comment, grouped by repo (default)
  comments rm <id>...    remove records by id; archives the touched queue first
  comments rm            interactive picker — pick by index or id
  comments clear         archive then empty every queue, across all repos
  comments path          print the comments dir
  comments -h, --help    show this help

queues live under ~/.local/share/comments (slug rule / -> %), archives under
its archive/ subdir. removals are recoverable. stdlib only; runs via `uv run`.\
"""

# ANSI styling, gated on a real terminal so piped/redirected output stays plain.
_TTY = sys.stdout.isatty()

# Body marker. Swap for another glyph here if you prefer.
MARKER = "▸"


def _c(code: str, s: str) -> str:
    return f"\033[{code}m{s}\033[0m" if _TTY else s


def bold(s: str) -> str:
    return _c("1", s)


def dim(s: str) -> str:
    return _c("2", s)


def cyan(s: str) -> str:
    return _c("36", s)


def yellow(s: str) -> str:
    return _c("33", s)


def queue_files() -> list[Path]:
    if not DIR.is_dir():
        return []
    return sorted(p for p in DIR.glob("*.jsonl") if p.parent == DIR)


def repo_of(f: Path) -> str:
    # slug rule is / -> %, so reverse it to recover the repo root
    return f.stem.replace("%", "/")


def load(f: Path) -> list[dict]:
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


def all_records() -> list[tuple[Path, dict]]:
    out = []
    for f in queue_files():
        for rec in load(f):
            out.append((f, rec))
    return out


def age(ts: str) -> str:
    """Human relative age from an ISO timestamp; '' if unparseable."""
    try:
        then = _dt.datetime.fromisoformat(ts)
    except (ValueError, TypeError):
        return ""
    secs = (_dt.datetime.now() - then).total_seconds()
    if secs < 90:
        return "just now"
    for div, unit in ((86400, "d"), (3600, "h"), (60, "m")):
        if secs >= div:
            return f"{int(secs // div)}{unit} ago"
    return "just now"


def fmt(rec: dict, tag: str = "") -> str:
    """Format a record. `tag` is a styled prefix (id/index) on the head line; the
    body sits flush-left under it, led by a fat MARKER glyph."""
    rel = rec.get("rel", rec.get("path", "?"))
    line = rec.get("line", "?")
    end = rec.get("end_line", line)
    span = f"{line}" if line == end else f"{line}-{end}"
    body = (rec.get("body", "") or "").replace("\n", " ")
    when = age(rec.get("ts", ""))
    head = f"{tag}{yellow(rec.get('id', '?'))}  {cyan(rel)}:{span}"
    if when:
        head += dim(f"  · {when}")
    return f"{head}\n{cyan(MARKER)} {body}"


def cmd_list() -> int:
    files = queue_files()
    counts = {f: load(f) for f in files}
    counts = {f: recs for f, recs in counts.items() if recs}
    if not counts:
        print(dim("no comments..."))
        return 0
    total = 0
    for f, recs in counts.items():
        print(f"\n{bold(repo_of(f))} {dim(f'({len(recs)})')}")
        for rec in recs:
            print(fmt(rec, tag=""))
            total += 1
    print(dim(f"\n{total} comment(s) across {len(counts)} repo(s)"))
    return 0


def archive(f: Path) -> Path:
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    ts = _dt.datetime.now().strftime("%Y%m%dT%H%M%S")
    dest = ARCHIVE / f"{f.stem}-{ts}.jsonl"
    shutil.copy2(f, dest)
    return dest


def remove_ids(ids: set[str]) -> int:
    found: set[str] = set()
    # map each queue file to the ids it holds
    touched: dict[Path, list[dict]] = {}
    for f in queue_files():
        recs = load(f)
        keep = [r for r in recs if r.get("id") not in ids]
        if len(keep) != len(recs):
            found.update(r.get("id") for r in recs if r.get("id") in ids)
            touched[f] = keep

    missing = ids - found
    if missing:
        print(f"not found: {', '.join(sorted(missing))}", file=sys.stderr)
    if not touched:
        return 1 if missing else 0

    for f, keep in touched.items():
        dest = archive(f)
        f.write_text("".join(json.dumps(r) + "\n" for r in keep))
        print(f"updated {repo_of(f)} (archived -> {dest})")
    print(f"removed {len(found)} comment(s)")
    return 0


def cmd_clear() -> int:
    """Archive then truncate every non-empty queue. Recoverable from archive/."""
    cleared = 0
    total = 0
    for f in queue_files():
        recs = load(f)
        if not recs:
            continue
        dest = archive(f)
        f.write_text("")
        cleared += 1
        total += len(recs)
        print(f"{bold(repo_of(f))} {dim(f'({len(recs)})')} archived -> {dim(str(dest))}")
    if not cleared:
        print(dim("(no comments queued)"))
        return 0
    print(f"\ncleared {total} comment(s) across {cleared} repo(s)")
    return 0


def cmd_rm(argv: list[str]) -> int:
    if argv:
        return remove_ids(set(argv))

    # interactive picker
    records = all_records()
    if not records:
        print(dim("(no comments queued)"))
        return 0
    print(bold("Select comments to remove:\n"))
    for i, (f, rec) in enumerate(records, 1):
        print(fmt(rec, tag=f"{dim(f'[{i:>3}]')} "))
    print()
    try:
        raw = input(
            "indices or ids to remove (space/comma separated, blank to cancel): "
        )
    except (EOFError, KeyboardInterrupt):
        print("\ncancelled")
        return 0
    tokens = raw.replace(",", " ").split()
    if not tokens:
        print("cancelled")
        return 0

    ids: set[str] = set()
    for tok in tokens:
        if tok.isdigit() and 1 <= int(tok) <= len(records):
            ids.add(records[int(tok) - 1][1].get("id"))
        else:
            ids.add(tok)
    return remove_ids(ids)


def main(argv: list[str]) -> int:
    cmd = argv[0] if argv else "list"
    rest = argv[1:]
    if cmd in ("-h", "--help", "help"):
        print(HELP)
        return 0
    if cmd == "list":
        return cmd_list()
    if cmd == "rm":
        return cmd_rm(rest)
    if cmd == "clear":
        return cmd_clear()
    if cmd == "path":
        print(DIR)
        return 0
    print(f"unknown command: {cmd}\n", file=sys.stderr)
    print(HELP, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
