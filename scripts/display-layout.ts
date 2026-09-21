#!/usr/bin/env bun

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const layoutNames = ["below", "left"] as const;
type LayoutName = (typeof layoutNames)[number];

type Profile = {
  args: string[];
  capturedAt: string;
};

type Config = {
  active?: LayoutName;
  layouts: Partial<Record<LayoutName, Profile>>;
};

const home = process.env.HOME;
if (!home) throw new Error("HOME is not set");

const configPath = join(
  process.env.XDG_CONFIG_HOME ?? join(home, ".config"),
  "display-layout",
  "layouts.json",
);

export function parseShellWords(input: string): string[] {
  const words: string[] = [];
  let word = "";
  let quote: "'" | '"' | undefined;
  let escaping = false;
  let started = false;

  for (const character of input.trim()) {
    if (escaping) {
      word += character;
      escaping = false;
      started = true;
      continue;
    }

    if (character === "\\" && quote !== "'") {
      escaping = true;
      started = true;
      continue;
    }

    if (quote) {
      if (character === quote) quote = undefined;
      else word += character;
      continue;
    }

    if (character === "'" || character === '"') {
      quote = character;
      started = true;
    } else if (/\s/.test(character)) {
      if (started) {
        words.push(word);
        word = "";
        started = false;
      }
    } else {
      word += character;
      started = true;
    }
  }

  if (escaping || quote) throw new Error("Malformed displayplacer command");
  if (started) words.push(word);
  return words;
}

export function extractDisplayplacerArgs(output: string): string[] {
  const commandLine = output
    .split("\n")
    .toReversed()
    .find((line) => /(?:^|\/)displayplacer\s+/.test(line.trim()));

  if (!commandLine) {
    throw new Error("displayplacer did not print a reusable layout command");
  }

  const words = parseShellWords(commandLine.trim());
  const commandIndex = words.findIndex((word) =>
    /(?:^|\/)displayplacer$/.test(word),
  );
  const args = words.slice(commandIndex + 1);
  if (commandIndex < 0 || args.length === 0) {
    throw new Error("Could not parse the displayplacer layout command");
  }
  return args;
}

export function nextLayout(active?: LayoutName): LayoutName {
  return active === "below" ? "left" : "below";
}

function isLayoutName(value: string | undefined): value is LayoutName {
  return layoutNames.includes(value as LayoutName);
}

function fail(message: string): never {
  console.error(`display-layout: ${message}`);
  process.exit(1);
}

function runDisplayplacer(args: string[]): string {
  if (!Bun.which("displayplacer")) {
    fail("displayplacer is missing; install it with: brew install displayplacer");
  }

  const result = Bun.spawnSync(["displayplacer", ...args], {
    stdout: "pipe",
    stderr: "pipe",
  });

  if (result.exitCode !== 0) {
    const detail = result.stderr.toString().trim();
    fail(detail || "displayplacer failed");
  }

  return result.stdout.toString();
}

async function readConfig(): Promise<Config> {
  try {
    return JSON.parse(await readFile(configPath, "utf8")) as Config;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { layouts: {} };
    throw error;
  }
}

async function writeConfig(config: Config): Promise<void> {
  await mkdir(dirname(configPath), { recursive: true });
  await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`);
}

async function capture(name: LayoutName): Promise<void> {
  const args = extractDisplayplacerArgs(runDisplayplacer(["list"]));
  const config = await readConfig();
  config.layouts[name] = { args, capturedAt: new Date().toISOString() };
  config.active = name;
  await writeConfig(config);
  console.log(`Captured '${name}' from the current display arrangement.`);
}

async function apply(name: LayoutName): Promise<void> {
  const config = await readConfig();
  const profile = config.layouts[name];
  if (!profile) fail(`no '${name}' profile; run: display-layout capture ${name}`);

  runDisplayplacer(profile.args);
  config.active = name;
  await writeConfig(config);
  console.log(`Applied '${name}'.`);
}

async function toggle(): Promise<void> {
  const config = await readConfig();
  const missing = layoutNames.filter((name) => !config.layouts[name]);
  if (missing.length) {
    fail(`missing profile(s): ${missing.join(", ")}`);
  }
  await apply(nextLayout(config.active));
}

async function status(): Promise<void> {
  const config = await readConfig();
  console.log(`Active: ${config.active ?? "unknown"}`);
  for (const name of layoutNames) {
    const profile = config.layouts[name];
    console.log(
      `${name}: ${profile ? `captured ${profile.capturedAt}` : "not captured"}`,
    );
  }
}

function usage(): void {
  console.log(`Usage:
  display-layout capture below|left  Save the current arrangement
  display-layout apply below|left    Apply a saved arrangement
  display-layout toggle              Switch to the other arrangement
  display-layout status              Show saved state`);
}

async function main(): Promise<void> {
  if (process.platform !== "darwin") fail("macOS only");

  const [command, name] = Bun.argv.slice(2);
  if (command === "capture" || command === "apply") {
    if (!isLayoutName(name)) fail(`expected one of: ${layoutNames.join(", ")}`);
    await (command === "capture" ? capture(name) : apply(name));
  } else if (command === "toggle") {
    await toggle();
  } else if (command === "status") {
    await status();
  } else {
    usage();
    if (command && command !== "help" && command !== "--help" && command !== "-h") {
      process.exitCode = 1;
    }
  }
}

if (import.meta.main) await main();
