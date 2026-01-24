#!/usr/bin/env bun
/**
 * Sort herdr tabs alphabetically (case-insensitive, ties by tab number).
 * Uses the socket API's tab.move since the CLI has no reorder command.
 *
 * Usage:
 *   bun sort-tabs.ts                  # current workspace
 *   bun sort-tabs.ts --workspace w9
 *   bun sort-tabs.ts --dry-run        # print order, don't move
 */

import { connect } from "net";
import { join } from "path";
import { homedir } from "os";

const SOCKET_PATH = process.env.HERDR_SOCKET_PATH ?? join(homedir(), ".config/herdr/herdr.sock");

type Tab = { tab_id: string; label: string; number: number };

function call(method: string, params: object): Promise<any> {
  return new Promise((resolve, reject) => {
    const sock = connect(SOCKET_PATH);
    let buf = "";
    sock.on("connect", () => sock.write(JSON.stringify({ id: "sort-tabs", method, params }) + "\n"));
    sock.on("data", (chunk) => {
      buf += chunk;
      if (buf.endsWith("\n")) sock.end();
    });
    sock.on("end", () => {
      const res = JSON.parse(buf);
      res.error ? reject(new Error(`${method}: ${JSON.stringify(res.error)}`)) : resolve(res.result);
    });
    sock.on("error", reject);
  });
}

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const wsIdx = args.indexOf("--workspace");
const workspaceId = wsIdx >= 0 ? args[wsIdx + 1] : process.env.HERDR_WORKSPACE_ID;
if (!workspaceId) {
  console.error("No workspace: pass --workspace <id> or run inside herdr");
  process.exit(1);
}

const listTabs = async (): Promise<Tab[]> => (await call("tab.list", { workspace_id: workspaceId })).tabs;

const sorted = [...(await listTabs())].sort(
  (a, b) => a.label.localeCompare(b.label, undefined, { sensitivity: "base" }) || a.number - b.number,
);

if (dryRun) {
  console.log(sorted.map((t) => t.label).join(", "));
  process.exit(0);
}

for (const [i, t] of sorted.entries()) await call("tab.move", { tab_id: t.tab_id, insert_index: i });

console.log((await listTabs()).map((t) => t.label).join(", "));
