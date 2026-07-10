#!/usr/bin/env python3
"""Move every pane from every other workspace into the current workspace.

Each moved pane lands in its own new tab (named after its original tab) in
the target workspace. Panes already in the target workspace are left alone.
"""
import json
import os
import subprocess
import sys

BIN = os.environ.get("HERDR_BIN_PATH") or "herdr"
PANE = os.environ.get("HERDR_PANE_ID")


def herdr(*args):
    res = subprocess.run([BIN, *args], capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit("herdr %s failed: %s" % (
            " ".join(args), (res.stderr or res.stdout).strip()))
    return res.stdout


def target_workspace_id():
    if PANE:
        info = json.loads(herdr("pane", "get", PANE))
        return info["result"]["pane"]["workspace_id"]
    workspaces = json.loads(herdr("workspace", "list"))["result"]["workspaces"]
    focused = next((w for w in workspaces if w["focused"]), workspaces[0])
    return focused["workspace_id"]


def main():
    target = target_workspace_id()

    tabs = {t["tab_id"]: t["label"] for t in
            json.loads(herdr("tab", "list"))["result"]["tabs"]}
    panes = json.loads(herdr("pane", "list"))["result"]["panes"]

    moved = 0
    for p in panes:
        if p["workspace_id"] == target:
            continue
        label = tabs.get(p["tab_id"]) or "pane"
        herdr("pane", "move", p["pane_id"], "--new-tab",
              "--workspace", target, "--label", label, "--no-focus")
        moved += 1

    print("moved %d pane(s) into workspace %s" % (moved, target))


if __name__ == "__main__":
    main()
