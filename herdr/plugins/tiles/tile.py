#!/usr/bin/env python3
"""Tile the current herdr pane into a target proportion.

Usage: tile.py <h|v> <fraction>
  h | v       axis. h = horizontal (left | right), v = vertical (top / bottom).
  <fraction>  0..1 share given to the CURRENT pane, which is the leading
              (left for h, top for v) section.

Behaviour:
  * If the current pane has no neighbour on that axis it is SPLIT so the
    current pane becomes the leading side at <fraction>.
  * If a neighbour already exists the divider is RESIZED to hit <fraction>
    instead of spawning a third pane -- this is what makes the "flip"
    actions re-proportion an existing 2-pane layout.

herdr semantics learned empirically (0.7.0):
  * `pane split --ratio R` -> the ORIGINAL (leading) pane keeps fraction R.
  * `pane resize --direction D --amount A` -> moves the current pane's shared
    edge toward D by fraction A of the split span (D toward the neighbour
    grows the current pane; away from it shrinks).
"""
import json
import os
import subprocess
import sys

BIN = os.environ.get("HERDR_BIN_PATH") or "herdr"
PANE = os.environ.get("HERDR_PANE_ID") or "--current"
EPS = 0.02  # don't bother resizing for sub-2% corrections


def herdr(*args):
    res = subprocess.run([BIN, "pane", *args], capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit("herdr pane %s failed: %s" % (
            " ".join(args), (res.stderr or res.stdout).strip()))
    return res.stdout


def pane_selector():
    return ["--current"] if PANE == "--current" else ["--pane", PANE]


def my_pane_id(lay):
    # `pane get` needs a real id; the HERDR_PANE_ID alias resolves fine.
    # When no env id was provided, fall back to the layout's focused pane.
    if PANE == "--current":
        return lay["focused_pane_id"]
    info = json.loads(herdr("get", PANE))
    return info["result"]["pane"]["pane_id"]


def find_neighbour(panes, me, axis):
    """Return the pane adjacent to `me` on the given axis, or None."""
    r = me["rect"]
    for p in panes:
        if p["pane_id"] == me["pane_id"]:
            continue
        q = p["rect"]
        if axis == "h":
            # share vertical extent and touch horizontally
            overlap = r["y"] < q["y"] + q["height"] and q["y"] < r["y"] + r["height"]
            touch = q["x"] == r["x"] + r["width"] or r["x"] == q["x"] + q["width"]
        else:
            overlap = r["x"] < q["x"] + q["width"] and q["x"] < r["x"] + r["width"]
            touch = q["y"] == r["y"] + r["height"] or r["y"] == q["y"] + q["height"]
        if overlap and touch:
            return p
    return None


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("h", "v"):
        sys.exit("usage: tile.py <h|v> <fraction 0..1>")
    axis = sys.argv[1]
    target = float(sys.argv[2])

    lay = json.loads(herdr("layout", *pane_selector()))["result"]["layout"]
    pid = my_pane_id(lay)

    # No neighbour on this axis yet -> split so the current pane leads at target.
    me = next((p for p in lay["panes"] if p["pane_id"] == pid), None)
    if me is None:
        sys.exit("could not locate current pane in layout")
    if find_neighbour(lay["panes"], me, axis) is None:
        direction = "right" if axis == "h" else "down"
        herdr("split", PANE, "--direction", direction,
              "--ratio", "%.4f" % target, "--no-focus")
        return

    # A neighbour exists -> nudge the divider toward `target`. A single resize
    # can be clamped (min pane size / per-call cap), so re-measure and repeat
    # until it converges or stops moving.
    for _ in range(12):
        lay = json.loads(herdr("layout", *pane_selector()))["result"]["layout"]
        me = next((p for p in lay["panes"] if p["pane_id"] == pid), None)
        neighbour = find_neighbour(lay["panes"], me, axis) if me else None
        if me is None or neighbour is None:
            return
        r, q = me["rect"], neighbour["rect"]
        if axis == "h":
            span = r["width"] + q["width"]
            cur = r["width"] / span
            leading = r["x"] < q["x"]
            # (grow current toward neighbour, grow neighbour toward current)
            grow_dir, shrink_dir = ("right", "left") if leading else ("left", "right")
        else:
            span = r["height"] + q["height"]
            cur = r["height"] / span
            leading = r["y"] < q["y"]
            grow_dir, shrink_dir = ("down", "up") if leading else ("up", "down")

        delta = target - cur
        if abs(delta) < EPS:
            return
        # A pane can only grow its shared divider; an outer edge is a wall.
        # Grow the current pane to enlarge it, or its neighbour to shrink it.
        if delta > 0:
            target_id, direction = me["pane_id"], grow_dir
        else:
            target_id, direction = neighbour["pane_id"], shrink_dir
        res = herdr("resize", "--pane", target_id,
                    "--direction", direction, "--amount", "%.4f" % abs(delta))
        if '"changed":true' not in res:
            return  # hit a limit -- stop rather than spin


if __name__ == "__main__":
    main()
