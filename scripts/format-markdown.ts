#!/usr/bin/env bun
/**
 * fmt-markdown.ts
 * Fixes spacing issues in synced Google Doc markdown exports:
 *   - blank line before/after each heading
 *   - remove hard line wraps, join continuation lines (default, deterministic)
 *   - blank line between consecutive prose lines (--paragraphs flag)
 *
 * Usage:
 *   bun scripts/fmt-markdown.ts <path>              # file or directory (relative to cwd, or absolute/~)
 *   bun scripts/fmt-markdown.ts .                   # format every .md under the current directory
 *   bun scripts/fmt-markdown.ts <path> --paragraphs # also fix paragraph spacing
 *   bun scripts/fmt-markdown.ts <path> --ai         # use Claude for unwrap (fallback)
 *   bun scripts/fmt-markdown.ts <path> --dry-run    # preview changes only
 *   (no path) defaults to resources/docs — the synced Google Doc exports
 */

import { readdir, readFile, writeFile, stat } from "fs/promises";
import { join, extname, resolve } from "path";
import { $ } from "bun";

const args = process.argv.slice(2);
const fixParagraphs = args.includes("--paragraphs");
const useAi = args.includes("--ai");
const dryRun = args.includes("--dry-run");

const ROOT = join(import.meta.dir, "..");

// Default to the synced Google Doc exports when no path is given
const targetArg =
  args.find((a) => !a.startsWith("--")) ?? join(ROOT, "resources/docs");

// Expand a leading ~ ourselves so quoted/literal tilde paths work, not just shell-expanded ones.
// Everything else — including "." and other relative paths — resolves against the current working
// directory, so you can cd into any folder and run `fmt-markdown.ts .` to format it.
const expandedArg = targetArg.startsWith("~")
  ? join(process.env.HOME ?? "", targetArg.slice(1))
  : targetArg;
const targetPath = resolve(expandedArg);

// Files/dirs to skip
const SKIP = new Set(["INDEX.md", "TEMPLATE.md", "_meta.md", "comments.md"]);

function isHeading(line: string): boolean {
  return /^#{1,6}\s/.test(line);
}

function isFrontmatterBoundary(line: string): boolean {
  return line.trim() === "---";
}

function isListItem(line: string): boolean {
  return /^\s*[-*+]\s/.test(line) || /^\s*\d+\.\s/.test(line);
}

function isCodeFence(line: string): boolean {
  return /^```/.test(line);
}

function isBlank(line: string): boolean {
  return line.trim() === "";
}

function formatMarkdown(content: string, paragraphMode: boolean): string {
  const lines = content.split("\n");
  const out: string[] = [];
  let inCode = false;
  let inFrontmatter = false;
  let frontmatterDone = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Track frontmatter (--- block at top of file)
    if (i === 0 && isFrontmatterBoundary(line)) {
      inFrontmatter = true;
      out.push(line);
      continue;
    }
    if (inFrontmatter && isFrontmatterBoundary(line) && i > 0) {
      inFrontmatter = false;
      frontmatterDone = true;
      out.push(line);
      continue;
    }
    if (inFrontmatter) {
      out.push(line);
      continue;
    }

    // Track code fences — don't touch content inside them
    if (isCodeFence(line)) {
      inCode = !inCode;
      out.push(line);
      continue;
    }
    if (inCode) {
      out.push(line);
      continue;
    }

    const prev = out.length > 0 ? out[out.length - 1] : "";

    if (isHeading(line)) {
      // Ensure blank line before heading (skip if already blank, or start of file, or after ---)
      if (out.length > 0 && !isBlank(prev) && !isFrontmatterBoundary(prev)) {
        out.push("");
      }
      out.push(line);
      // Ensure blank line after heading
      const next = lines[i + 1];
      if (next !== undefined && !isBlank(next)) {
        out.push("");
      }
    } else if (
      paragraphMode &&
      !isBlank(line) &&
      !isListItem(line) &&
      !isBlank(prev) &&
      !isHeading(prev)
    ) {
      // In paragraph mode: two consecutive non-empty prose lines need a blank between them
      out.push("");
      out.push(line);
    } else {
      out.push(line);
    }
  }

  // Collapse 3+ consecutive blank lines down to 2
  const collapsed: string[] = [];
  let blanks = 0;
  for (const line of out) {
    if (isBlank(line)) {
      blanks++;
      if (blanks <= 2) collapsed.push(line);
    } else {
      blanks = 0;
      collapsed.push(line);
    }
  }

  return collapsed.join("\n");
}

async function unwrapWithClaude(content: string): Promise<string> {
  const prompt = `Reformat the markdown file below. Remove all hard line wraps — join wrapped continuation lines so each sentence or list item is a single unbroken line. Rules:
- Preserve blank lines between paragraphs
- Do NOT touch code blocks (triple backtick fences)
- Do NOT touch tables
- Unwrap blockquote content but preserve the > prefix on the resulting single line
- Do NOT add, remove, or alter any content — only reflow line breaks
- Output only the reformatted file contents, no commentary or explanation

<file>
${content}
</file>`;
  const result =
    await $`claude --dangerously-skip-permissions -p ${prompt}`.text();
  const trimmed = result.trim() + "\n";

  // Sanity check: if Claude's output is less than half the input length, something went wrong
  // (e.g. Claude responded with a question instead of reformatting the content)
  if (trimmed.length < content.length / 2) {
    throw new Error(
      `Claude output suspiciously short (${trimmed.length} chars vs ${content.length} input). Aborting to avoid data loss.\nClaude said: ${trimmed.slice(0, 200)}`,
    );
  }

  return trimmed;
}

function unwrapMarkdown(content: string): string {
  const lines = content.split("\n");
  const out: string[] = [];
  let buffer: string[] = [];
  let bufferKind: "none" | "paragraph" | "list" | "blockquote" = "none";
  let inCode = false;
  let inFrontmatter = false;

  function flush() {
    if (buffer.length === 0) return;
    out.push(buffer.join(" "));
    buffer = [];
    bufferKind = "none";
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Frontmatter passthrough
    if (i === 0 && line.trim() === "---") {
      inFrontmatter = true;
      out.push(line);
      continue;
    }
    if (inFrontmatter) {
      out.push(line);
      if (line.trim() === "---" && i > 0) inFrontmatter = false;
      continue;
    }

    // Code fences
    if (/^```/.test(line)) {
      flush();
      inCode = !inCode;
      out.push(line);
      continue;
    }
    if (inCode) {
      out.push(line);
      continue;
    }

    // Tables — flush buffer, pass through verbatim
    if (/^\s*\|/.test(line)) {
      flush();
      out.push(line);
      continue;
    }

    // Blank line — paragraph break
    if (line.trim() === "") {
      flush();
      out.push(line);
      continue;
    }

    // Headings
    if (/^#{1,6}\s/.test(line)) {
      flush();
      out.push(line);
      continue;
    }

    // Blockquote
    if (/^>\s?/.test(line)) {
      if (bufferKind === "blockquote") {
        buffer.push(line.replace(/^>\s?/, "").trim());
      } else {
        flush();
        buffer.push(line);
        bufferKind = "blockquote";
      }
      continue;
    }

    // List item start (-, *, +, or N.)
    if (/^\s*([-*+]|\d+\.)\s/.test(line)) {
      flush();
      buffer.push(line);
      bufferKind = "list";
      continue;
    }

    // Continuation line — join into existing buffer (paragraph or list item),
    // stripping leading whitespace so list-continuation indents collapse
    if (bufferKind !== "none") {
      buffer.push(line.trim());
    } else {
      buffer.push(line);
      bufferKind = "paragraph";
    }
  }

  flush();
  return out.join("\n");
}

async function processFile(filePath: string): Promise<void> {
  const filename = filePath.split("/").pop() ?? "";
  if (SKIP.has(filename)) return;

  const original = await readFile(filePath, "utf-8");
  const unwrapped = useAi
    ? await unwrapWithClaude(original)
    : unwrapMarkdown(original);
  const formatted = formatMarkdown(unwrapped, fixParagraphs);

  if (original === formatted) return;

  if (dryRun) {
    console.log(`[dry-run] would update: ${filePath.replace(ROOT + "/", "")}`);
    return;
  }

  await writeFile(filePath, formatted, "utf-8");
  console.log(`formatted: ${filePath.replace(ROOT + "/", "")}`);
}

async function processPath(p: string): Promise<void> {
  const info = await stat(p).catch(() => null);
  if (!info) {
    console.error(`not found: ${p}`);
    process.exit(1);
  }

  if (info.isFile()) {
    if (extname(p) === ".md") await processFile(p);
    return;
  }

  if (info.isDirectory()) {
    const entries = await readdir(p, { withFileTypes: true });
    for (const entry of entries) {
      const child = join(p, entry.name);
      if (entry.isDirectory()) {
        await processPath(child);
      } else if (entry.isFile() && extname(entry.name) === ".md") {
        await processFile(child);
      }
    }
  }
}

await processPath(targetPath);
