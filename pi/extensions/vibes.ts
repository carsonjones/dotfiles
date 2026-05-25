// https://github.com/nicobailon/pi-powerline-footer
import { complete, type Context } from "@mariozechner/pi-ai";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

type VibeMode = "generate" | "file";

type VibeConfig = {
  theme: string | null;
  mode: VibeMode;
  modelSpec: string | null; // null/current = use the active Pi model
  fallback: string;
  timeout: number;
  refreshInterval: number;
  promptTemplate: string;
  maxLength: number;
};

const DEFAULT_PROMPT = `Generate a 2-4 word "{theme}" themed loading message ending in "...".

Task: {task}

Be creative and unexpected. Avoid obvious/clichéd phrases for this theme.
The message should hint at the task using theme vocabulary.
{exclude}
Output only the message, nothing else.`;

const BATCH_PROMPT = `Generate {count} unique 2-4 word loading messages for a "{theme}" theme.
Each message should end with "..."
Be creative, varied, and thematic. No duplicates.
Output one message per line, nothing else. No numbering, no bullets.`;

const SYSTEM_PROMPT =
  "You generate short themed loading messages and reply with the requested text only.";
const MAX_RECENT_VIBES = 5;

let config = loadConfig();
let extensionCtx: ExtensionContext | null = null;
let currentGeneration: AbortController | null = null;
let isStreaming = false;
let lastVibeTime = 0;
let recentVibes: string[] = [];
let vibeCache: string[] = [];
let vibeCacheTheme: string | null = null;
let vibeSeed = Date.now();
let vibeIndex = 0;

function settingsPath(): string {
  return join(
    process.env.HOME || process.env.USERPROFILE || homedir(),
    ".pi",
    "agent",
    "settings.json",
  );
}

function vibesDir(): string {
  return join(
    process.env.HOME || process.env.USERPROFILE || homedir(),
    ".pi",
    "agent",
    "vibes",
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readSettings(): Record<string, unknown> {
  const path = settingsPath();
  try {
    if (!existsSync(path)) return {};
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    return isRecord(parsed) ? parsed : {};
  } catch (error) {
    console.debug("[working-vibes] failed to read settings:", error);
    return {};
  }
}

function writeSettings(settings: Record<string, unknown>): boolean {
  const path = settingsPath();
  try {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
    return true;
  } catch (error) {
    console.debug("[working-vibes] failed to write settings:", error);
    return false;
  }
}

function updateSettings(
  mutator: (settings: Record<string, unknown>) => void,
): boolean {
  const settings = readSettings();
  mutator(settings);
  return writeSettings(settings);
}

function loadConfig(): VibeConfig {
  const settings = readSettings();
  const rawTheme =
    typeof settings.workingVibe === "string" ? settings.workingVibe : null;
  const rawMode = settings.workingVibeMode;
  const refreshSeconds =
    typeof settings.workingVibeRefreshInterval === "number"
      ? settings.workingVibeRefreshInterval
      : 30;
  const maxLength =
    typeof settings.workingVibeMaxLength === "number"
      ? settings.workingVibeMaxLength
      : 65;
  const modelSpec =
    typeof settings.workingVibeModel === "string" &&
    settings.workingVibeModel !== "current"
      ? settings.workingVibeModel
      : null;

  return {
    theme: rawTheme?.toLowerCase() === "off" ? null : rawTheme,
    mode: rawMode === "file" ? "file" : "generate",
    modelSpec,
    fallback:
      typeof settings.workingVibeFallback === "string"
        ? settings.workingVibeFallback
        : "Working",
    timeout: 3000,
    refreshInterval: Math.max(0, refreshSeconds) * 1000,
    promptTemplate:
      typeof settings.workingVibePrompt === "string"
        ? settings.workingVibePrompt
        : DEFAULT_PROMPT,
    maxLength: Math.max(4, Math.floor(maxLength)),
  };
}

function setTheme(theme: string | null): boolean {
  config = { ...config, theme };
  recentVibes = [];
  return updateSettings((settings) => {
    if (theme === null) delete settings.workingVibe;
    else settings.workingVibe = theme;
  });
}

function setMode(mode: VibeMode): boolean {
  config = { ...config, mode };
  return updateSettings((settings) => {
    if (mode === "generate") delete settings.workingVibeMode;
    else settings.workingVibeMode = mode;
  });
}

function setModel(modelSpec: string | null): boolean {
  config = { ...config, modelSpec };
  return updateSettings((settings) => {
    if (!modelSpec || modelSpec === "current") delete settings.workingVibeModel;
    else settings.workingVibeModel = modelSpec;
  });
}

function vibeFileSlug(theme: string): string {
  return (
    theme
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9_-]+/g, "-")
      .replace(/-+/g, "-")
      .replace(/^[-_]+|[-_]+$/g, "") || "theme"
  );
}

function vibeFilePath(theme: string): string {
  return join(vibesDir(), `${vibeFileSlug(theme)}.txt`);
}

function loadVibesFromFile(theme: string): string[] {
  try {
    const file = vibeFilePath(theme);
    if (!existsSync(file)) return [];
    return readFileSync(file, "utf8")
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line && line.endsWith("..."));
  } catch (error) {
    console.debug("[working-vibes] failed to load vibe file:", error);
    return [];
  }
}

function saveVibesToFile(theme: string, vibes: string[]): void {
  mkdirSync(vibesDir(), { recursive: true });
  writeFileSync(vibeFilePath(theme), vibes.join("\n") + "\n");
}

function mulberry32(seed: number): () => number {
  return () => {
    let t = (seed += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffledVibe(vibes: string[], index: number, seed: number): string {
  if (!vibes.length) return `${config.fallback}...`;
  const rng = mulberry32(seed);
  const indices = Array.from({ length: vibes.length }, (_, i) => i);
  for (let i = indices.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [indices[i], indices[j]] = [indices[j], indices[i]];
  }
  return vibes[indices[index % vibes.length]];
}

function nextFileVibe(): string {
  if (!config.theme) return `${config.fallback}...`;
  if (vibeCacheTheme !== config.theme) {
    vibeCache = loadVibesFromFile(config.theme);
    vibeCacheTheme = config.theme;
    vibeSeed = Date.now();
    vibeIndex = 0;
  }
  const vibe = shuffledVibe(vibeCache, vibeIndex, vibeSeed);
  vibeIndex++;
  return vibe;
}

function buildPrompt(theme: string, taskText: string): string {
  const exclude = recentVibes.length
    ? `Don't use: ${recentVibes.join(", ")}`
    : "";
  return config.promptTemplate
    .replace(/\{theme\}/g, theme)
    .replace(/\{task\}/g, taskText.slice(0, 150))
    .replace(/\{exclude\}/g, exclude);
}

function parseVibeResponse(response: string): string {
  let vibe = response.trim().split("\n")[0]?.trim() ?? "";
  vibe = vibe.replace(/^["']|["']$/g, "");
  if (!vibe.endsWith("...")) vibe = vibe.replace(/\.+$/, "") + "...";
  if (vibe.length > config.maxLength)
    vibe = vibe.slice(0, config.maxLength - 3) + "...";
  return vibe && vibe !== "..." ? vibe : `${config.fallback}...`;
}

function aiContext(prompt: string): Context {
  return {
    systemPrompt: SYSTEM_PROMPT,
    messages: [
      {
        role: "user",
        content: [{ type: "text", text: prompt }],
        timestamp: Date.now(),
      },
    ],
  };
}

function resolveModel(ctx: ExtensionContext) {
  if (!config.modelSpec) return ctx.model;
  const slash = config.modelSpec.indexOf("/");
  if (slash === -1) return undefined;
  const provider = config.modelSpec.slice(0, slash);
  const modelId = config.modelSpec.slice(slash + 1);
  return provider && modelId
    ? ctx.modelRegistry.find(provider, modelId)
    : undefined;
}

async function generateVibe(
  taskText: string,
  signal: AbortSignal,
): Promise<string> {
  if (!extensionCtx || !config.theme) return `${config.fallback}...`;
  const model = resolveModel(extensionCtx);
  if (!model) {
    console.debug(
      "[working-vibes] vibe model not found",
      config.modelSpec ?? "current",
    );
    return `${config.fallback}...`;
  }

  const auth = await extensionCtx.modelRegistry.getApiKeyAndHeaders(model);
  if (!auth.ok) {
    console.debug("[working-vibes] vibe model auth failed", auth.error);
    return `${config.fallback}...`;
  }

  const response = await complete(
    model,
    aiContext(buildPrompt(config.theme, taskText)),
    {
      apiKey: auth.apiKey,
      headers: auth.headers,
      signal,
      maxTokens: 32,
    },
  );
  const text = response.content.find((c) => c.type === "text")?.text ?? "";
  if (!text && response.stopReason === "error")
    console.debug("[working-vibes] generation failed", response.errorMessage);
  return parseVibeResponse(text);
}

function track(vibe: string): void {
  if (vibe === `${config.fallback}...`) return;
  recentVibes = [vibe, ...recentVibes.filter((old) => old !== vibe)].slice(
    0,
    MAX_RECENT_VIBES,
  );
}

async function updateVibe(
  taskText: string,
  setWorkingMessage: (message?: string) => void,
): Promise<void> {
  if (config.mode === "file") {
    setWorkingMessage(nextFileVibe());
    return;
  }

  const controller = new AbortController();
  currentGeneration?.abort();
  currentGeneration = controller;
  const timeoutSignal = AbortSignal.timeout(config.timeout);
  const combinedSignal = AbortSignal.any([controller.signal, timeoutSignal]);

  try {
    const vibe = await generateVibe(taskText, combinedSignal);
    if (isStreaming && !controller.signal.aborted) {
      track(vibe);
      setWorkingMessage(vibe);
    }
  } catch (error) {
    if (!(error instanceof Error && error.name === "AbortError"))
      console.debug("[working-vibes] generation failed", error);
  }
}

function recentAgentText(ctx: ExtensionContext): string | undefined {
  const branch = ctx.sessionManager?.getBranch?.() ?? [];
  for (let i = branch.length - 1; i >= 0; i--) {
    const entry = branch[i];
    if (
      entry.type !== "message" ||
      entry.message?.role !== "assistant" ||
      !Array.isArray(entry.message.content)
    )
      continue;
    for (const block of entry.message.content) {
      if (block.type === "text" && block.text?.trim())
        return block.text.trim().slice(0, 200);
    }
  }
  return undefined;
}

function toolHint(
  toolName: string,
  input: Record<string, unknown>,
  ctx: ExtensionContext,
): string {
  const agentText = recentAgentText(ctx);
  if (agentText && agentText.length > 10) return agentText;
  if (toolName === "read" && input.path) return `reading file: ${input.path}`;
  if (toolName === "write" && input.path) return `writing file: ${input.path}`;
  if (toolName === "edit" && input.path) return `editing file: ${input.path}`;
  if (toolName === "bash" && input.command)
    return `running command: ${String(input.command).slice(0, 60)}`;
  return `using ${toolName} tool`;
}

async function generateBatch(
  theme: string,
  count: number,
): Promise<{
  success: boolean;
  count: number;
  filePath: string;
  error?: string;
}> {
  const filePath = vibeFilePath(theme);
  if (!extensionCtx)
    return {
      success: false,
      count: 0,
      filePath,
      error: "Extension not initialized",
    };
  const model = resolveModel(extensionCtx);
  if (!model)
    return {
      success: false,
      count: 0,
      filePath,
      error: `Model not found: ${config.modelSpec ?? "current"}`,
    };
  const auth = await extensionCtx.modelRegistry.getApiKeyAndHeaders(model);
  if (!auth.ok)
    return { success: false, count: 0, filePath, error: auth.error };

  const safeCount = Math.min(Math.max(Math.floor(count), 1), 500);
  const prompt = BATCH_PROMPT.replace(/\{theme\}/g, theme).replace(
    /\{count\}/g,
    String(safeCount),
  );

  try {
    const response = await complete(model, aiContext(prompt), {
      apiKey: auth.apiKey,
      headers: auth.headers,
      signal: AbortSignal.timeout(30000),
      maxTokens: Math.min(4096, Math.max(256, safeCount * 16)),
    });
    const text = response.content.find((c) => c.type === "text")?.text ?? "";
    if (!text)
      return {
        success: false,
        count: 0,
        filePath,
        error: response.errorMessage || "Empty response from model",
      };

    const vibes = text
      .split("\n")
      .map((line) =>
        line
          .trim()
          .replace(/^["'\d.\-)\s]+/, "")
          .replace(/["']$/g, ""),
      )
      .filter(Boolean)
      .map((line) =>
        line.endsWith("...") ? line : line.replace(/\.+$/, "") + "...",
      )
      .filter((line) => line.length > 3 && line !== "...");

    if (!vibes.length)
      return {
        success: false,
        count: 0,
        filePath,
        error: "No valid vibes generated",
      };
    saveVibesToFile(theme, vibes);
    if (vibeCacheTheme === theme) vibeCacheTheme = null;
    return { success: true, count: vibes.length, filePath };
  } catch (error) {
    return {
      success: false,
      count: 0,
      filePath,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

export default function workingVibes(pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    extensionCtx = ctx;
    config = loadConfig();
    isStreaming = false;
  });

  pi.on("before_agent_start", async (event, ctx) => {
    if (!ctx.hasUI || !config.theme) return;
    ctx.ui.setWorkingMessage(`Channeling ${config.theme}...`);
    lastVibeTime = Date.now();
    void updateVibe(event.prompt, (message?: string) =>
      ctx.ui.setWorkingMessage(message),
    );
  });

  pi.on("agent_start", async () => {
    isStreaming = true;
  });

  pi.on("tool_call", async (event, ctx) => {
    if (!ctx.hasUI || !config.theme || !isStreaming) return;
    const now = Date.now();
    if (now - lastVibeTime < config.refreshInterval) return;
    lastVibeTime = now;
    void updateVibe(
      toolHint(event.toolName, event.input, ctx),
      (message?: string) => ctx.ui.setWorkingMessage(message),
    );
  });

  pi.on("agent_end", async (_event, ctx) => {
    isStreaming = false;
    currentGeneration?.abort();
    if (ctx.hasUI) ctx.ui.setWorkingMessage(undefined);
  });

  pi.on("session_shutdown", async () => {
    isStreaming = false;
    currentGeneration?.abort();
    extensionCtx = null;
  });

  pi.registerCommand("vibe", {
    description:
      "Set themed Working... messages. Usage: /vibe [theme|off|mode|model|generate]",
    handler: async (args, ctx) => {
      extensionCtx = ctx;
      config = loadConfig();
      const text = args?.trim() ?? "";
      const parts = text.split(/\s+/).filter(Boolean);
      const sub = parts[0]?.toLowerCase();

      if (!text) {
        const model =
          config.modelSpec ??
          `current (${ctx.model?.provider}/${ctx.model?.id})`;
        let status = `Vibe: ${config.theme || "off"} | Mode: ${config.mode} | Model: ${model}`;
        if (config.theme && config.mode === "file") {
          const count = loadVibesFromFile(config.theme).length;
          status += count ? ` | File: ${count} vibes` : " | File: not found";
        }
        ctx.ui.notify(status, "info");
        return;
      }

      if (sub === "off") {
        ctx.ui.notify(
          setTheme(null) ? "Vibe disabled" : "Vibe disabled (not persisted)",
          "info",
        );
        return;
      }

      if (sub === "model") {
        const modelSpec = parts.slice(1).join(" ");
        if (!modelSpec) {
          ctx.ui.notify(
            `Current vibe model: ${config.modelSpec ?? `current (${ctx.model?.provider}/${ctx.model?.id})`}`,
            "info",
          );
          return;
        }
        if (modelSpec !== "current" && !modelSpec.includes("/")) {
          ctx.ui.notify(
            "Use /vibe model provider/modelId, or /vibe model current",
            "error",
          );
          return;
        }
        ctx.ui.notify(
          setModel(modelSpec === "current" ? null : modelSpec)
            ? `Vibe model set to: ${modelSpec}`
            : `Vibe model set to: ${modelSpec} (not persisted)`,
          "info",
        );
        return;
      }

      if (sub === "mode") {
        const mode = parts[1]?.toLowerCase();
        if (!mode) {
          ctx.ui.notify(`Current vibe mode: ${config.mode}`, "info");
          return;
        }
        if (mode !== "generate" && mode !== "file") {
          ctx.ui.notify("Invalid mode. Use: generate or file", "error");
          return;
        }
        if (
          mode === "file" &&
          config.theme &&
          !existsSync(vibeFilePath(config.theme))
        ) {
          ctx.ui.notify(
            `No vibe file for "${config.theme}". Run /vibe generate ${config.theme} first`,
            "error",
          );
          return;
        }
        ctx.ui.notify(
          setMode(mode)
            ? `Vibe mode set to: ${mode}`
            : `Vibe mode set to: ${mode} (not persisted)`,
          "info",
        );
        return;
      }

      if (sub === "generate") {
        const theme = parts[1];
        const count = Number.isFinite(Number.parseInt(parts[2] ?? "", 10))
          ? Number.parseInt(parts[2]!, 10)
          : 100;
        if (!theme) {
          ctx.ui.notify("Usage: /vibe generate <theme> [count]", "error");
          return;
        }
        ctx.ui.notify(
          `Generating ${Math.min(Math.max(count, 1), 500)} vibes for "${theme}"...`,
          "info",
        );
        const result = await generateBatch(theme, count);
        ctx.ui.notify(
          result.success
            ? `Generated ${result.count} vibes → ${result.filePath}`
            : `Failed to generate vibes: ${result.error}`,
          result.success ? "info" : "error",
        );
        return;
      }

      const theme = text;
      const persisted = setTheme(theme);
      if (config.mode === "file" && !existsSync(vibeFilePath(theme))) {
        ctx.ui.notify(
          `Vibe set to: ${theme} (file missing; run /vibe generate ${theme})${persisted ? "" : " (not persisted)"}`,
          "warning",
        );
      } else {
        ctx.ui.notify(
          `Vibe set to: ${theme}${persisted ? "" : " (not persisted)"}`,
          "info",
        );
      }
    },
  });
}
