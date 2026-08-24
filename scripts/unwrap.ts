#!/usr/bin/env bun

import { parseArgs } from "node:util";

export function unwrap(input: string): string {
  const text = input.replaceAll("\r\n", "\n").replaceAll("\r", "\n");
  const lines = text.split("\n");
  const output: string[] = [];
  const tableLines = findTableLines(lines);
  let paragraph: Paragraph | undefined;
  let fence: Fence | undefined;

  const possibleFrontmatterEnd =
    lines[0]?.trim() === "---"
      ? lines.findIndex((line, index) => index > 0 && line.trim() === "---")
      : -1;
  const frontmatterEnd =
    possibleFrontmatterEnd > 0 &&
    lines
      .slice(1, possibleFrontmatterEnd)
      .some((line) => /^[A-Za-z0-9_-]+:\s*/.test(line))
      ? possibleFrontmatterEnd
      : -1;

  const flush = () => {
    if (!paragraph) return;
    output.push(`${paragraph.prefix}${paragraph.text}`);
    paragraph = undefined;
  };

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];

    if (frontmatterEnd > 0 && index <= frontmatterEnd) {
      flush();
      output.push(line);
      continue;
    }

    const quoted = parseQuote(line);
    if (fence) {
      output.push(line);
      if (
        quoted.quotePrefix === fence.quotePrefix &&
        isClosingFence(quoted.content, fence)
      ) {
        fence = undefined;
      }
      continue;
    }

    const openingFence = parseOpeningFence(quoted.content);
    if (openingFence) {
      flush();
      output.push(line);
      fence = { ...openingFence, quotePrefix: quoted.quotePrefix };
      continue;
    }

    if (line.trim() === "") {
      flush();
      output.push(line);
      continue;
    }

    const parsed = parseLine(line);

    if (
      tableLines.has(index) ||
      isStructural(parsed.content, parsed.rawContent)
    ) {
      flush();
      output.push(line);
      continue;
    }

    if (
      paragraph?.kind === "list" &&
      !parsed.listPrefix &&
      parsed.quotePrefix === paragraph.quotePrefix &&
      !endsWithHardBreak(paragraph.text)
    ) {
      append(paragraph, parsed.content);
      continue;
    }

    if (parsed.listPrefix) {
      flush();
      paragraph = {
        kind: "list",
        prefix: `${parsed.quotePrefix}${parsed.listPrefix}`,
        quotePrefix: parsed.quotePrefix,
        text: cleanSegment(parsed.content),
      };
      continue;
    }

    if (
      paragraph &&
      paragraph.quotePrefix === parsed.quotePrefix &&
      !endsWithHardBreak(paragraph.text)
    ) {
      append(paragraph, parsed.content);
      continue;
    }

    flush();
    paragraph = {
      kind: "prose",
      prefix: `${parsed.quotePrefix}${parsed.indentPrefix}`,
      quotePrefix: parsed.quotePrefix,
      text: cleanSegment(parsed.content),
    };
  }

  flush();
  return output.join("\n");
}

type Fence = {
  marker: "`" | "~";
  length: number;
  quotePrefix: string;
};

type Paragraph = {
  kind: "prose" | "list";
  prefix: string;
  quotePrefix: string;
  text: string;
};

function findTableLines(lines: string[]) {
  const tableLines = new Set<number>();

  for (let index = 1; index < lines.length; index++) {
    const delimiter = parseQuote(lines[index]);
    const header = parseQuote(lines[index - 1]);
    if (
      delimiter.quotePrefix !== header.quotePrefix ||
      !isTableDelimiter(delimiter.content) ||
      !hasPipe(header.content)
    ) {
      continue;
    }

    tableLines.add(index - 1);
    tableLines.add(index);
    for (let row = index + 1; row < lines.length; row++) {
      const parsed = parseQuote(lines[row]);
      if (
        parsed.quotePrefix !== delimiter.quotePrefix ||
        !hasPipe(parsed.content)
      ) {
        break;
      }
      tableLines.add(row);
    }
  }

  return tableLines;
}

function isTableDelimiter(line: string) {
  return /^ {0,3}\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(line);
}

function hasPipe(line: string) {
  return /(^|[^\\])\|/.test(line);
}

function parseQuote(line: string) {
  const quote = line.match(/^((?: {0,3}>[ \t]?)+)(.*)$/);
  return {
    quotePrefix: quote?.[1] ?? "",
    content: quote?.[2] ?? line,
  };
}

function parseLine(line: string) {
  const quoted = parseQuote(line);
  const list = quoted.content.match(/^( {0,3}(?:[-+*]|\d+[.)])[ \t]+)(.*)$/);
  const indent = list ? undefined : quoted.content.match(/^( {1,3})(?=\S)/);

  return {
    quotePrefix: quoted.quotePrefix,
    listPrefix: list?.[1] ?? "",
    indentPrefix: indent?.[1] ?? "",
    rawContent: quoted.content,
    content: list?.[2] ?? quoted.content.slice(indent?.[1].length ?? 0),
  };
}

function parseOpeningFence(content: string) {
  const match = content.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
  if (!match || (match[1][0] === "`" && match[2].includes("`"))) return;

  return {
    marker: match[1][0] as "`" | "~",
    length: match[1].length,
  };
}

function isClosingFence(content: string, fence: Fence) {
  const match = content.match(/^ {0,3}(`+|~+)[ \t]*$/);
  return match?.[1][0] === fence.marker && match[1].length >= fence.length;
}

function append(paragraph: Paragraph, content: string) {
  if (endsWithHardBreak(paragraph.text)) return;
  const next = cleanSegment(content);
  if (!next) return;
  paragraph.text = `${paragraph.text.trimEnd()} ${next}`;
}

function cleanSegment(content: string) {
  const segment = content.trimStart();
  return endsWithHardBreak(segment) ? segment : segment.trimEnd();
}

function endsWithHardBreak(line: string) {
  return /(?: {2,}|\\)$/.test(line);
}

function isStructural(content: string, originalLine: string) {
  return (
    /^ {0,3}#{1,6}(?:[ \t]|$)/.test(content) ||
    /^ {0,3}(?:(?:\*\s*){3,}|(?:-\s*){3,}|(?:_\s*){3,})$/.test(content) ||
    /^ {0,3}(?:=+|-+)\s*$/.test(content) ||
    /^\s*\|.*\|\s*$/.test(content) ||
    /^\s*\[[^\]]+\]:\s+/.test(content) ||
    /^\s*<!--/.test(content) ||
    /^\s*<\/?[A-Za-z][^>]*>\s*$/.test(content) ||
    (/^(?: {4}|\t)/.test(originalLine) &&
      !originalLine.trimStart().startsWith(">"))
  );
}

async function main() {
  const { values, positionals } = parseArgs({
    args: Bun.argv.slice(2),
    allowPositionals: true,
    options: {
      "in-place": { type: "boolean", short: "i" },
      help: { type: "boolean", short: "h" },
    },
  });

  if (values.help) {
    console.log(
      `Usage: unwrap [-i] [FILE ...]\n\nWithout files, reads stdin and writes stdout.\nWith -i, rewrites each file in place.`,
    );
    return;
  }

  if (values["in-place"] && positionals.length === 0) {
    throw new Error("--in-place requires at least one file");
  }

  if (positionals.length === 0) {
    process.stdout.write(unwrap(await Bun.stdin.text()));
    return;
  }

  for (const path of positionals) {
    const result = unwrap(await Bun.file(path).text());
    if (values["in-place"]) await Bun.write(path, result);
    else process.stdout.write(result);
  }
}

if (import.meta.main) {
  main().catch((error) => {
    console.error(`unwrap: ${error instanceof Error ? error.message : error}`);
    process.exitCode = 1;
  });
}
