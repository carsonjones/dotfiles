#!/usr/bin/env bun
/**
 * Finds past Claude Code and Codex agent sessions by content, and maintains
 * memory/sessions.md -- the greppable one-line-per-session index.
 *
 * Transcript stores:
 *   ~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl        (main sessions)
 *   ~/.claude/projects/<sanitized-cwd>/<session-id>/subagents/*  (subagent runs)
 *   ~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl
 *
 * Gotchas this bakes in (learned the hard way 2026-09-01):
 *   - codex user turns live at payload.type=message, role=user; the first ones
 *     are the AGENTS.md preamble and <user_instructions>, not the real prompt
 *   - codex spawns a parallel approval-reviewer rollout with the SAME timestamp
 *     whose "user" turns are transcript dumps -- noise, skipped by default
 *   - claude subagent transcripts sit in <session-id>/subagents/, skipped by default
 *   - macOS stat is `stat -f '%Sm' -t <fmt>`, not `-U` (that's GNU)
 *
 * Usage:
 *   bun scripts/find-session.ts attendee validation      # sessions matching ALL patterns
 *   bun scripts/find-session.ts --tool codex --since 2026-08-01 receipt
 *   bun scripts/find-session.ts --cwd main --limit 5 snowflake
 *   bun scripts/find-session.ts --reviewers --subagents  # include the noise
 *   bun scripts/find-session.ts --rebuild-index          # regenerate memory/sessions.md
 *   echo '<hook json>' | bun scripts/find-session.ts --append-index
 *   ... --index <path>                                   # write index elsewhere
 */
import { readFile, writeFile } from "fs/promises";
import { existsSync } from "fs";
import { homedir } from "os";
import { basename, dirname, join } from "path";

const CLAUDE_ROOT = join(homedir(), ".claude", "projects");
const CODEX_ROOT = join(homedir(), ".codex", "sessions");
/**
 * The index lives in the workspace, NOT next to this script -- this file is
 * symlinked in from ~/src/dotfiles, so import.meta.dir points at dotfiles.
 * Resolution order: --index flag > $SESSION_INDEX > $CLAUDE_PROJECT_DIR/memory > ~/main/memory.
 */
let INDEX_PATH =
  process.env.SESSION_INDEX ||
  join(process.env.CLAUDE_PROJECT_DIR || join(homedir(), "main"), "memory", "sessions.md");
const HEAD_BYTES = 2_000_000; // first user turn is always near the top
const INDEX_HEADER = `# Session Index

One line per agent session, newest last. Built by scripts/hook-SessionEnd.sh
(claude) and \`bun scripts/find-session.ts --rebuild-index\` (claude + codex).
Grep this before grepping transcripts. Resume: \`claude --resume <id>\` from the
listed cwd, or \`codex resume <id>\`.
`;

type Tool = "claude" | "codex";
type Kind = "main" | "subagent" | "reviewer";

interface Session {
  tool: Tool;
  kind: Kind;
  id: string;
  /** YYYY-MM-DD HH:MM local */
  when: string;
  cwd: string;
  prompt: string;
  path: string;
}

// --- parsing ---------------------------------------------------------------

/** Reads only the head of a transcript -- enough for metadata + first prompt. */
async function head(path: string): Promise<string> {
  return await Bun.file(path).slice(0, HEAD_BYTES).text();
}

function textOf(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((part) =>
      part && typeof part === "object" && typeof (part as any).text === "string"
        ? (part as any).text
        : ""
    )
    .join(" ");
}

/** Injected context, tool results and slash-command plumbing -- not a prompt. */
function isBoilerplate(text: string): boolean {
  const t = text.trim();
  if (!t) return true;
  if (t.startsWith("<")) return true; // system-reminder, user_instructions, command-message
  if (t.startsWith("#")) return true; // AGENTS.md / CLAUDE.md preamble
  if (t.startsWith("[Request interrupted")) return true;
  if (t.startsWith("Caveat:")) return true;
  return false;
}

function localStamp(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso.slice(0, 16).replace("T", " ");
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function parseClaude(path: string, body: string): Session | null {
  const kind: Kind = dirname(path).endsWith("subagents") ? "subagent" : "main";
  let when = "";
  let cwd = "";
  let id = basename(path, ".jsonl");
  let prompt = "";

  for (const line of body.split("\n")) {
    if (!line.startsWith("{")) continue;
    let rec: any;
    try {
      rec = JSON.parse(line);
    } catch {
      continue; // truncated tail of the head slice
    }
    if (!when && rec.timestamp) when = localStamp(rec.timestamp);
    if (!cwd && rec.cwd) cwd = rec.cwd;
    if (rec.sessionId) id = rec.sessionId;
    if (!prompt && rec.type === "user") {
      const text = textOf(rec.message?.content);
      if (!isBoilerplate(text)) prompt = text.trim();
    }
    if (prompt && when && cwd) break;
  }
  if (!prompt && !when) return null;
  return { tool: "claude", kind, id, when, cwd, prompt, path };
}

function parseCodex(path: string, body: string): Session | null {
  // rollout-2026-08-28T16-14-16-01a04a39-2cd9-7b71-be5e-218fb890d4d7.jsonl
  const m = basename(path).match(
    /^rollout-(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-\d{2}-([0-9a-f-]{36})\.jsonl$/
  );
  if (!m) return null;
  const [, date, hh, mm, id] = m;
  let cwd = "";
  let prompt = "";
  let kind: Kind = "main";

  for (const line of body.split("\n")) {
    if (!line.startsWith("{")) continue;
    let rec: any;
    try {
      rec = JSON.parse(line);
    } catch {
      continue;
    }
    const p = rec.payload ?? rec;
    if (!cwd && typeof p.cwd === "string") cwd = p.cwd;
    if (!prompt && p.type === "message" && p.role === "user") {
      const text = textOf(p.content);
      if (!isBoilerplate(text)) prompt = text.trim();
    }
    if (prompt && cwd) break;
  }
  if (prompt.startsWith("The following is the Codex agent history")) {
    kind = "reviewer"; // the approval-assessment sidecar, not a real session
  }
  return { tool: "codex", kind, id, when: `${date} ${hh}:${mm}`, cwd, prompt, path };
}

async function parse(path: string): Promise<Session | null> {
  const body = await head(path);
  return path.startsWith(CODEX_ROOT) ? parseCodex(path, body) : parseClaude(path, body);
}

// --- discovery -------------------------------------------------------------

async function allTranscripts(tool?: Tool): Promise<string[]> {
  const out: string[] = [];
  const roots: [Tool, string][] = [
    ["claude", CLAUDE_ROOT],
    ["codex", CODEX_ROOT],
  ];
  for (const [name, root] of roots) {
    if (tool && tool !== name) continue;
    if (!existsSync(root)) continue;
    const glob = new Bun.Glob("**/*.jsonl");
    for await (const rel of glob.scan({ cwd: root })) out.push(join(root, rel));
  }
  return out;
}

/** rg -l for each pattern, intersected: a session must match them all. */
async function grepFiles(patterns: string[], roots: string[]): Promise<string[]> {
  let keep: Set<string> | null = null;
  for (const pattern of patterns) {
    const proc = Bun.spawn(["rg", "-l", "-i", "--no-messages", "-e", pattern, ...roots], {
      stdout: "pipe",
      stderr: "ignore",
    });
    const hits = (await new Response(proc.stdout).text())
      .split("\n")
      .filter((l) => l.endsWith(".jsonl"));
    const set = new Set(hits);
    keep = keep === null ? set : new Set([...keep].filter((f) => set.has(f)));
    if (keep.size === 0) break;
  }
  return [...(keep ?? [])];
}

/** First matching line, trimmed to a window around the match. */
async function excerpt(path: string, pattern: string): Promise<string> {
  const proc = Bun.spawn(["rg", "-i", "-m", "1", "-N", "--no-filename", "-e", pattern, path], {
    stdout: "pipe",
    stderr: "ignore",
  });
  const line = (await new Response(proc.stdout).text()).slice(0, 500_000);
  if (!line) return "";
  let at = 0;
  try {
    at = Math.max(0, line.search(new RegExp(pattern, "i")));
  } catch {
    at = 0;
  }
  const start = Math.max(0, at - 70);
  return (start > 0 ? "..." : "") + line.slice(start, at + 140).replace(/\s+/g, " ").trim();
}

// --- output ----------------------------------------------------------------

const tilde = (p: string) => (p.startsWith(homedir()) ? "~" + p.slice(homedir().length) : p);
const oneLine = (s: string, n: number) =>
  s.replace(/\s+/g, " ").slice(0, n) + (s.replace(/\s+/g, " ").length > n ? "..." : "");

function resumeCmd(s: Session): string {
  return s.tool === "codex" ? `codex resume ${s.id}` : `claude --resume ${s.id}`;
}

function indexLine(s: Session): string {
  return `- ${s.when} ${s.tool} ${tilde(s.cwd) || "?"} ${s.id} -- ${oneLine(s.prompt, 120) || "(no prompt)"}`;
}

// --- index maintenance -----------------------------------------------------

async function readIndex(): Promise<string> {
  if (!existsSync(INDEX_PATH)) return `${INDEX_HEADER}\n`;
  return await readFile(INDEX_PATH, "utf-8");
}

async function appendIndex(hookJson: string) {
  let hook: any = {};
  try {
    hook = JSON.parse(hookJson || "{}");
  } catch {
    /* SessionEnd payload malformed; fall through to the guard below */
  }
  const path = hook.transcript_path;
  if (!path || !existsSync(path)) return; // nothing to index (e.g. --no-session-persistence)
  const session = await parse(path);
  if (!session || session.kind !== "main") return;
  if (!session.prompt) return; // session ended before a real prompt
  if (!session.cwd) session.cwd = hook.cwd ?? "";

  const current = await readIndex();
  if (current.includes(` ${session.id} `)) return; // already indexed
  await writeFile(INDEX_PATH, `${current.trimEnd()}\n${indexLine(session)}\n`);
}

async function rebuildIndex() {
  const files = await allTranscripts();
  const sessions: Session[] = [];
  for (const file of files) {
    const s = await parse(file).catch(() => null);
    if (s && s.kind === "main" && s.prompt) sessions.push(s);
  }
  sessions.sort((a, b) => a.when.localeCompare(b.when));
  const body = sessions.map(indexLine).join("\n");
  await writeFile(INDEX_PATH, `${INDEX_HEADER}\n${body}\n`);
  console.log(`${INDEX_PATH}: ${sessions.length} sessions`);
}

// --- search ----------------------------------------------------------------

interface Opts {
  patterns: string[];
  tool?: Tool;
  since?: string;
  cwd?: string;
  limit: number;
  reviewers: boolean;
  subagents: boolean;
}

async function search(o: Opts) {
  const roots: string[] = [];
  if (o.tool !== "codex" && existsSync(CLAUDE_ROOT)) roots.push(CLAUDE_ROOT);
  if (o.tool !== "claude" && existsSync(CODEX_ROOT)) roots.push(CODEX_ROOT);

  const files = o.patterns.length
    ? await grepFiles(o.patterns, roots)
    : await allTranscripts(o.tool);

  const sessions: Session[] = [];
  for (const file of files) {
    const s = await parse(file).catch(() => null);
    if (!s) continue;
    if (s.kind === "reviewer" && !o.reviewers) continue;
    if (s.kind === "subagent" && !o.subagents) continue;
    if (o.since && s.when.slice(0, 10) < o.since) continue;
    if (o.cwd && !s.cwd.includes(o.cwd)) continue;
    sessions.push(s);
  }
  sessions.sort((a, b) => b.when.localeCompare(a.when));

  const shown = sessions.slice(0, o.limit);
  for (const s of shown) {
    const tag = s.kind === "main" ? s.tool : `${s.tool}/${s.kind}`;
    console.log(`\n${s.when}  ${tag}  ${tilde(s.cwd) || "?"}`);
    console.log(`  prompt: ${oneLine(s.prompt, 200) || "(none)"}`);
    if (o.patterns.length) {
      const hit = await excerpt(s.path, o.patterns[0]);
      if (hit) console.log(`  match:  ${hit}`);
    }
    console.log(`  resume: ${resumeCmd(s)}`);
    console.log(`  file:   ${tilde(s.path)}`);
  }
  const more = sessions.length - shown.length;
  console.log(
    `\n${sessions.length} session${sessions.length === 1 ? "" : "s"}${more > 0 ? ` (${more} more, raise --limit)` : ""}`
  );
}

// --- cli -------------------------------------------------------------------

async function main() {
  const argv = process.argv.slice(2);
  const ix = argv.indexOf("--index");
  if (ix !== -1) {
    INDEX_PATH = argv[ix + 1];
    argv.splice(ix, 2);
  }
  if (argv.includes("--append-index")) {
    await appendIndex(await new Response(Bun.stdin.stream()).text());
    return;
  }
  if (argv.includes("--rebuild-index")) {
    await rebuildIndex();
    return;
  }

  const o: Opts = {
    patterns: [],
    limit: 10,
    reviewers: false,
    subagents: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--tool") o.tool = argv[++i] as Tool;
    else if (a === "--since") o.since = argv[++i];
    else if (a === "--cwd") o.cwd = argv[++i];
    else if (a === "--limit") o.limit = Number(argv[++i]);
    else if (a === "--reviewers") o.reviewers = true;
    else if (a === "--subagents") o.subagents = true;
    else if (a.startsWith("--")) throw new Error(`unknown flag: ${a}`);
    else o.patterns.push(a);
  }
  if (o.tool && o.tool !== "claude" && o.tool !== "codex") {
    throw new Error("--tool must be claude or codex");
  }
  await search(o);
}

await main();
