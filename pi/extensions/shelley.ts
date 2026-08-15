import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { getMarkdownTheme } from "@mariozechner/pi-coding-agent";
import { Box, Container, Markdown, Text } from "@mariozechner/pi-tui";
import { Type } from "typebox";

type ShelleyState = {
  conversationId: string | null;
};

type ShelleyMessage = {
  sequence_id?: number;
  type?: string;
  text?: string;
  end_of_turn?: boolean;
};

const STATE_ENTRY = "shelley-conversation";
const RESPONSE_MESSAGE = "shelley-response";
const TIMEOUT_MS = 15 * 60 * 1000;

let conversationId: string | null = null;

function parseJsonLines<T>(value: string): T[] {
  const parsed: T[] = [];
  for (const line of value.split("\n")) {
    if (!line.trim()) continue;
    try {
      parsed.push(JSON.parse(line) as T);
    } catch {
      // Ignore non-JSON diagnostics. Command failures are handled from exit codes.
    }
  }
  return parsed;
}

function restoreState(ctx: ExtensionContext): void {
  conversationId = null;
  for (const entry of ctx.sessionManager.getEntries()) {
    if (entry.type !== "custom" || entry.customType !== STATE_ENTRY) continue;
    const state = entry.data as ShelleyState | undefined;
    conversationId = state?.conversationId ?? null;
  }
}

function saveState(pi: ExtensionAPI): void {
  pi.appendEntry<ShelleyState>(STATE_ENTRY, { conversationId });
}

async function readShelleyMessages(
  pi: ExtensionAPI,
  id: string,
  signal?: AbortSignal,
): Promise<ShelleyMessage[]> {
  const read = await pi.exec("shelley", ["client", "read", id], { signal, timeout: 30_000 });
  if (read.code !== 0) {
    throw new Error((read.stderr || read.stdout || `shelley read exited ${read.code}`).trim());
  }
  return parseJsonLines<ShelleyMessage>(read.stdout);
}

async function waitForShelleyResponse(
  pi: ExtensionAPI,
  id: string,
  afterSequence: number,
  signal?: AbortSignal,
): Promise<string> {
  const deadline = Date.now() + TIMEOUT_MS;
  while (Date.now() < deadline) {
    const messages = await readShelleyMessages(pi, id, signal);
    const response = messages.find(
      (message) =>
        (message.sequence_id ?? 0) > afterSequence &&
        message.type === "agent" &&
        message.end_of_turn === true &&
        Boolean(message.text?.trim()),
    )?.text?.trim();
    if (response) return response;

    await new Promise<void>((resolve, reject) => {
      const onAbort = () => {
        clearTimeout(timeout);
        reject(signal?.reason ?? new Error("Aborted"));
      };
      const timeout = setTimeout(() => {
        signal?.removeEventListener("abort", onAbort);
        resolve();
      }, 1000);
      signal?.addEventListener("abort", onAbort, { once: true });
    });
  }
  throw new Error("Timed out waiting for Shelley");
}

async function askShelley(
  pi: ExtensionAPI,
  prompt: string,
  cwd: string,
  signal?: AbortSignal,
  startNew = false,
): Promise<{ conversationId: string; response: string }> {
  if (startNew) conversationId = null;

  const previousMessages = conversationId ? await readShelleyMessages(pi, conversationId, signal) : [];
  const afterSequence = Math.max(0, ...previousMessages.map((message) => message.sequence_id ?? 0));

  const chatArgs = ["client", "chat", "-p", prompt, "-cwd", cwd];
  if (conversationId) chatArgs.push("-c", conversationId);
  else chatArgs.push("-disable-notifications");

  const chat = await pi.exec("shelley", chatArgs, { signal, timeout: TIMEOUT_MS });
  if (chat.code !== 0) {
    throw new Error((chat.stderr || chat.stdout || `shelley chat exited ${chat.code}`).trim());
  }

  const result = parseJsonLines<{ conversation_id?: string }>(chat.stdout).at(-1);
  if (!result?.conversation_id) throw new Error("Shelley did not return a conversation ID");

  conversationId = result.conversation_id;
  saveState(pi);

  const response = await waitForShelleyResponse(pi, conversationId, afterSequence, signal);
  return { conversationId, response };
}

export default function shelley(pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => restoreState(ctx));

  pi.registerMessageRenderer(RESPONSE_MESSAGE, (message, { outputPad }, theme) => {
    const details = message.details as { conversationId?: string } | undefined;
    const container = new Container();
    const box = new Box(outputPad, 1, (text) => theme.bg("customMessageBg", text));
    box.addChild(new Text(theme.fg("accent", theme.bold("Shelley")), 0, 0));
    box.addChild(new Markdown(message.content, 0, 1, getMarkdownTheme()));
    if (details?.conversationId) {
      box.addChild(new Text(theme.fg("dim", details.conversationId), 0, 0));
    }
    container.addChild(box);
    return container;
  });

  pi.registerCommand("shelley", {
    description: "Talk to Shelley; use /shelley new <message> to start fresh",
    handler: async (args, ctx) => {
      const trimmed = args.trim();
      if (trimmed === "status") {
        ctx.ui.notify(conversationId ? `Shelley conversation: ${conversationId}` : "No active Shelley conversation", "info");
        return;
      }
      if (trimmed === "new") {
        conversationId = null;
        saveState(pi);
        ctx.ui.notify("Started a fresh Shelley conversation", "info");
        return;
      }

      const newMatch = /^new\s+([\s\S]+)$/i.exec(trimmed);
      const prompt = newMatch?.[1].trim() ?? trimmed;
      if (!prompt) {
        ctx.ui.notify("Usage: /shelley <message> | /shelley new <message> | /shelley status", "warning");
        return;
      }

      ctx.ui.setWorkingMessage("Talking to Shelley...");
      try {
        const result = await askShelley(pi, prompt, ctx.cwd, undefined, Boolean(newMatch));
        pi.sendMessage({
          customType: RESPONSE_MESSAGE,
          content: result.response,
          display: true,
          details: { conversationId: result.conversationId },
        });
      } catch (error) {
        ctx.ui.notify(`Shelley failed: ${error instanceof Error ? error.message : String(error)}`, "error");
      } finally {
        ctx.ui.setWorkingMessage();
      }
    },
  });

  pi.registerTool({
    name: "ask_shelley",
    label: "Ask Shelley",
    description: "Ask the separate Shelley coding agent for a second opinion or delegated work.",
    promptSnippet: "Ask the Shelley coding agent",
    promptGuidelines: ["Use ask_shelley when the user explicitly asks Pi to consult or delegate to Shelley."],
    parameters: Type.Object({
      prompt: Type.String({ description: "Self-contained message or task for Shelley" }),
      newConversation: Type.Optional(Type.Boolean({ description: "Start a fresh Shelley conversation" })),
    }),
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      onUpdate?.({ content: [{ type: "text", text: "Talking to Shelley..." }] });
      try {
        const result = await askShelley(pi, params.prompt, ctx.cwd, signal, params.newConversation ?? false);
        return {
          content: [{ type: "text", text: result.response }],
          details: { conversationId: result.conversationId },
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Shelley failed: ${error instanceof Error ? error.message : String(error)}` }],
          details: { conversationId, error: true },
          isError: true,
        };
      }
    },
  });
}
