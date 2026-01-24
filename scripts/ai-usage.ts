#!/usr/bin/env bun
/**
 * Print Cursor / Claude / ChatGPT (Codex) usage from local logins.
 *
 * Usage:
 *   bun scripts/ai-usage.ts              # all providers
 *   bun scripts/ai-usage.ts cursor
 *   bun scripts/ai-usage.ts claude
 *   bun scripts/ai-usage.ts chatgpt      # alias: codex
 *   bun scripts/ai-usage.ts --json
 */

import { Database } from "bun:sqlite";
import { homedir } from "node:os";
import { join } from "node:path";

type Provider = "cursor" | "claude" | "chatgpt";

type Window = {
  label: string;
  usedPct: number | null;
  detail?: string;
  resetsAt?: string | null;
};

type Snapshot = {
  provider: Provider;
  plan?: string;
  email?: string;
  windows: Window[];
  note?: string;
  error?: string;
};

const home = homedir();
const args = process.argv.slice(2);
const jsonMode = args.includes("--json");
const want = args.filter((a) => a !== "--json").map((a) => a.toLowerCase());

const providers: Provider[] = (() => {
  if (want.length === 0) return ["cursor", "claude", "chatgpt"];
  const out: Provider[] = [];
  for (const w of want) {
    if (w === "cursor") out.push("cursor");
    else if (w === "claude") out.push("claude");
    else if (w === "chatgpt" || w === "codex" || w === "openai") out.push("chatgpt");
    else {
      console.error(`unknown provider: ${w} (cursor|claude|chatgpt)`);
      process.exit(2);
    }
  }
  return out;
})();

function fmtPct(n: number | null | undefined): string {
  if (n == null || Number.isNaN(n)) return "—";
  return `${Math.round(n * 10) / 10}%`;
}

function fmtUsd(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

function fmtReset(isoOrEpoch: string | number | null | undefined): string | null {
  if (isoOrEpoch == null) return null;
  const d =
    typeof isoOrEpoch === "number"
      ? new Date(isoOrEpoch < 1e12 ? isoOrEpoch * 1000 : isoOrEpoch)
      : new Date(isoOrEpoch);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function relativeReset(isoOrEpoch: string | number | null | undefined): string | null {
  if (isoOrEpoch == null) return null;
  const ms =
    typeof isoOrEpoch === "number"
      ? isoOrEpoch < 1e12
        ? isoOrEpoch * 1000
        : isoOrEpoch
      : new Date(isoOrEpoch).getTime();
  if (Number.isNaN(ms)) return null;
  const sec = Math.max(0, Math.round((ms - Date.now()) / 1000));
  if (sec < 60) return `${sec}s`;
  if (sec < 3600) return `${Math.round(sec / 60)}m`;
  if (sec < 86400) return `${Math.round(sec / 3600)}h`;
  return `${Math.round(sec / 86400)}d`;
}

async function fetchJson(
  url: string,
  init: RequestInit,
): Promise<{ ok: true; data: unknown } | { ok: false; status: number; body: string }> {
  const res = await fetch(url, init);
  const body = await res.text();
  if (!res.ok) return { ok: false, status: res.status, body: body.slice(0, 200) };
  try {
    return { ok: true, data: JSON.parse(body) };
  } catch {
    return { ok: false, status: res.status, body: body.slice(0, 200) };
  }
}

function readCursorAuth(): { token: string; email?: string; plan?: string } {
  const dbPath = join(
    home,
    "Library/Application Support/Cursor/User/globalStorage/state.vscdb",
  );
  const db = new Database(dbPath, { readonly: true });
  try {
    const get = (key: string) =>
      db.query("SELECT value FROM ItemTable WHERE key = ?").get(key) as
        | { value: string | Uint8Array }
        | null;
    const asStr = (v: string | Uint8Array | undefined) =>
      v == null ? undefined : typeof v === "string" ? v : Buffer.from(v).toString("utf8");
    const token = asStr(get("cursorAuth/accessToken")?.value);
    if (!token) throw new Error("cursorAuth/accessToken missing — sign into Cursor");
    return {
      token,
      email: asStr(get("cursorAuth/cachedEmail")?.value),
      plan: asStr(get("cursorAuth/stripeMembershipType")?.value),
    };
  } finally {
    db.close();
  }
}

async function cursorUsage(): Promise<Snapshot> {
  try {
    const auth = readCursorAuth();
    const res = await fetchJson(
      "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${auth.token}`,
          "Content-Type": "application/json",
          "Connect-Protocol-Version": "1",
        },
        body: "{}",
      },
    );
    if (!res.ok) {
      return { provider: "cursor", error: `HTTP ${res.status}: ${res.body}` };
    }
    const d = res.data as {
      billingCycleEnd?: string;
      planUsage?: {
        includedSpend?: number;
        remaining?: number;
        limit?: number;
        totalPercentUsed?: number;
        autoPercentUsed?: number;
        apiPercentUsed?: number;
      };
      displayMessage?: string;
    };
    const pu = d.planUsage ?? {};
    const limit = pu.limit ?? 0;
    const used = pu.includedSpend ?? (limit && pu.remaining != null ? limit - pu.remaining : 0);
    // Prefer spend/limit — totalPercentUsed is often a tiny fraction that doesn't match the UI.
    const includedPct = limit ? (used / limit) * 100 : (pu.totalPercentUsed ?? null);
    const endMs = d.billingCycleEnd ? Number(d.billingCycleEnd) : null;
    const windows: Window[] = [
      {
        label: "included",
        usedPct: includedPct,
        detail: limit ? `${fmtUsd(used)} / ${fmtUsd(limit)}` : undefined,
        resetsAt: endMs != null ? new Date(endMs).toISOString() : null,
      },
    ];
    if (pu.autoPercentUsed != null || pu.apiPercentUsed != null) {
      windows.push({
        label: "auto",
        usedPct: pu.autoPercentUsed ?? null,
      });
      windows.push({
        label: "api",
        usedPct: pu.apiPercentUsed ?? null,
      });
    }
    return {
      provider: "cursor",
      plan: auth.plan,
      email: auth.email,
      windows,
      note: d.displayMessage,
    };
  } catch (e) {
    return { provider: "cursor", error: String(e instanceof Error ? e.message : e) };
  }
}

function readClaudeOauth(): {
  accessToken: string;
  subscriptionType?: string;
} {
  const proc = Bun.spawnSync(
    ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
    { stdout: "pipe", stderr: "pipe" },
  );
  if (proc.exitCode !== 0) {
    throw new Error("Claude Code credentials not in Keychain — run `claude` and sign in");
  }
  const blob = JSON.parse(proc.stdout.toString());
  const oauth = blob.claudeAiOauth;
  if (!oauth?.accessToken) throw new Error("claudeAiOauth.accessToken missing");
  return oauth;
}

async function claudeUsage(): Promise<Snapshot> {
  try {
    const oauth = readClaudeOauth();
    const res = await fetchJson("https://api.anthropic.com/api/oauth/usage", {
      headers: {
        Authorization: `Bearer ${oauth.accessToken}`,
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-code/2.1.303",
      },
    });
    if (!res.ok) {
      return { provider: "claude", error: `HTTP ${res.status}: ${res.body}` };
    }
    const d = res.data as {
      five_hour?: { utilization?: number; resets_at?: string };
      seven_day?: { utilization?: number; resets_at?: string };
      iguana_necktie?: {
        utilization?: number;
        used_dollars?: number;
        limit_dollars?: number;
        remaining_dollars?: number;
        resets_at?: string;
      };
      extra_usage?: {
        is_enabled?: boolean;
        credits_ever_enabled?: boolean;
        used_credits?: number;
        monthly_limit?: number;
        utilization?: number;
        disabled_reason?: string;
      };
    };
    const windows: Window[] = [
      {
        label: "5h",
        usedPct: d.five_hour?.utilization ?? null,
        resetsAt: d.five_hour?.resets_at ?? null,
      },
      {
        label: "weekly",
        usedPct: d.seven_day?.utilization ?? null,
        resetsAt: d.seven_day?.resets_at ?? null,
      },
    ];
    const iguana = d.iguana_necktie;
    if (iguana?.limit_dollars != null) {
      windows.push({
        label: "extra pool",
        usedPct:
          iguana.utilization != null
            ? iguana.limit_dollars
              ? (iguana.used_dollars ?? iguana.utilization) / iguana.limit_dollars * 100
              : iguana.utilization
            : null,
        detail:
          iguana.used_dollars != null
            ? `$${iguana.used_dollars.toFixed(2)} / $${iguana.limit_dollars}`
            : undefined,
        resetsAt: iguana.resets_at ?? null,
      });
    }
    const extra = d.extra_usage;
    if (extra?.credits_ever_enabled || extra?.is_enabled) {
      windows.push({
        label: "payg credits",
        usedPct: extra.utilization ?? null,
        detail:
          extra.used_credits != null && extra.monthly_limit != null
            ? `$${extra.used_credits.toFixed(2)} / $${extra.monthly_limit}`
            : undefined,
      });
    }
    return {
      provider: "claude",
      plan: oauth.subscriptionType,
      windows,
    };
  } catch (e) {
    return { provider: "claude", error: String(e instanceof Error ? e.message : e) };
  }
}

async function readCodexAuth(): Promise<{ accessToken: string; accountId?: string }> {
  const path = join(home, ".codex/auth.json");
  const file = Bun.file(path);
  if (!(await file.exists())) throw new Error("~/.codex/auth.json missing — run `codex login`");
  const auth = await file.json() as {
    tokens?: { access_token?: string; account_id?: string };
  };
  const token = auth.tokens?.access_token;
  if (!token) throw new Error("codex tokens.access_token missing");
  return { accessToken: token, accountId: auth.tokens?.account_id };
}

async function chatgptUsage(): Promise<Snapshot> {
  try {
    const auth = await readCodexAuth();
    const headers: Record<string, string> = {
      Authorization: `Bearer ${auth.accessToken}`,
      "User-Agent": "codex-cli",
      Accept: "application/json",
    };
    if (auth.accountId) headers["ChatGPT-Account-ID"] = auth.accountId;
    const res = await fetchJson("https://chatgpt.com/backend-api/wham/usage", {
      headers,
    });
    if (!res.ok) {
      return { provider: "chatgpt", error: `HTTP ${res.status}: ${res.body}` };
    }
    const d = res.data as {
      email?: string;
      plan_type?: string;
      rate_limit?: {
        primary_window?: {
          used_percent?: number;
          reset_at?: number;
          reset_after_seconds?: number;
        };
        secondary_window?: {
          used_percent?: number;
          reset_at?: number;
          reset_after_seconds?: number;
        };
      };
      rate_limit_reset_credits?: { available_count?: number };
      credits?: { balance?: string; has_credits?: boolean };
    };
    const primary = d.rate_limit?.primary_window;
    const secondary = d.rate_limit?.secondary_window;
    const windows: Window[] = [
      {
        label: "5h",
        usedPct: primary?.used_percent ?? null,
        resetsAt: primary?.reset_at != null ? new Date(primary.reset_at * 1000).toISOString() : null,
      },
      {
        label: "weekly",
        usedPct: secondary?.used_percent ?? null,
        resetsAt:
          secondary?.reset_at != null
            ? new Date(secondary.reset_at * 1000).toISOString()
            : null,
      },
    ];
    const banked = d.rate_limit_reset_credits?.available_count;
    return {
      provider: "chatgpt",
      plan: d.plan_type,
      email: d.email,
      windows,
      note: banked != null ? `${banked} banked reset${banked === 1 ? "" : "s"}` : undefined,
    };
  } catch (e) {
    return { provider: "chatgpt", error: String(e instanceof Error ? e.message : e) };
  }
}

function printHuman(snaps: Snapshot[]) {
  for (const s of snaps) {
    const title = s.provider === "chatgpt" ? "chatgpt (codex)" : s.provider;
    const head = [title, s.plan, s.email].filter(Boolean).join(" · ");
    console.log(head);
    if (s.error) {
      console.log(`  error: ${s.error}`);
      console.log();
      continue;
    }
    for (const w of s.windows) {
      const bits = [`${w.label}: ${fmtPct(w.usedPct)}`];
      if (w.detail) bits.push(w.detail);
      const when = fmtReset(w.resetsAt ?? undefined);
      const rel = relativeReset(w.resetsAt ?? undefined);
      if (when) bits.push(`resets ${when}${rel ? ` (${rel})` : ""}`);
      console.log(`  ${bits.join("  ·  ")}`);
    }
    if (s.note) console.log(`  ${s.note}`);
    console.log();
  }
}

const fetchers: Record<Provider, () => Promise<Snapshot>> = {
  cursor: cursorUsage,
  claude: claudeUsage,
  chatgpt: chatgptUsage,
};

const snaps = await Promise.all(providers.map((p) => fetchers[p]()));

if (jsonMode) {
  console.log(JSON.stringify(snaps, null, 2));
} else {
  printHuman(snaps);
}

const failed = snaps.some((s) => s.error);
process.exit(failed ? 1 : 0);
