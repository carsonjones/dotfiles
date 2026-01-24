/**
 * Trailboss handoff extension - transfer current Pi context into a Trailboss job.
 *
 * Usage:
 *   /trailboss act implement phase one of this plan
 *   /trailboss ask check whether this approach has edge cases
 *   /tb-act fix the follow-up issue
 *   /tb-ask explain the code path
 *   /tbact fix the follow-up issue
 *   /tbask explain the code path
 *
 * The generated prompt opens in an editor for review, then gets dispatched via:
 *   trailboss act <prompt>
 *   trailboss ask <prompt>
 */

import type { AgentMessage } from "@mariozechner/pi-agent-core";
import { complete, type Message } from "@mariozechner/pi-ai";
import type { ExtensionAPI, ExtensionCommandContext, SessionEntry } from "@mariozechner/pi-coding-agent";
import { BorderedLoader, convertToLlm, serializeConversation } from "@mariozechner/pi-coding-agent";

const SYSTEM_PROMPT = `You are a context transfer assistant. Given a conversation history, a Trailboss mode, and the user's goal for a background agent job, generate a focused prompt that:

1. Summarizes relevant context from the conversation: decisions made, approaches taken, key findings, and constraints
2. Lists relevant files that were discussed, read, or modified
3. Clearly states the next task based on the user's goal
4. Is self-contained so the Trailboss rider can proceed without the old conversation
5. Respects the Trailboss mode:
   - ask: answer, explain, investigate, and report back. Do not modify files.
   - act: implement, fix, refactor, or otherwise make code changes as needed.

Format your response as the exact prompt to pass to Trailboss. Be concise but include all necessary context. Do not include preamble like "Here's the prompt".

Example output format:
## Context
We've been working on X. Key decisions:
- Decision 1
- Decision 2

Files involved:
- path/to/file1.ts
- path/to/file2.ts

## Task
[Clear description of what to do next based on the user's goal]

## Mode
[ask or act instructions]`;

type TrailbossMode = "act" | "ask";

function entryToMessage(entry: SessionEntry): AgentMessage | undefined {
  if (entry.type === "message") return entry.message;
  if (entry.type === "compaction") {
    return {
      role: "compactionSummary",
      summary: entry.summary,
      tokensBefore: entry.tokensBefore,
      timestamp: new Date(entry.timestamp).getTime(),
    };
  }
  return undefined;
}

function getHandoffMessages(branch: SessionEntry[]): AgentMessage[] {
  let compactionIndex = -1;
  for (let i = branch.length - 1; i >= 0; i--) {
    if (branch[i].type === "compaction") {
      compactionIndex = i;
      break;
    }
  }

  if (compactionIndex < 0) {
    return branch.map(entryToMessage).filter((message) => message !== undefined);
  }

  const compaction = branch[compactionIndex];
  const firstKeptIndex =
    compaction.type === "compaction" ? branch.findIndex((entry) => entry.id === compaction.firstKeptEntryId) : -1;
  const compactedBranch = [
    compaction,
    ...(firstKeptIndex >= 0 ? branch.slice(firstKeptIndex, compactionIndex) : []),
    ...branch.slice(compactionIndex + 1),
  ];
  return compactedBranch.map(entryToMessage).filter((message) => message !== undefined);
}

function parseTrailbossArgs(args: string): { mode: TrailbossMode; goal: string } | null {
  const trimmed = args.trim();
  const match = /^(act|ask)\b\s*(.*)$/i.exec(trimmed);
  if (!match) return null;
  const mode = match[1].toLowerCase() as TrailbossMode;
  const goal = match[2].trim();
  return goal ? { mode, goal } : null;
}

async function generatePrompt(mode: TrailbossMode, goal: string, ctx: ExtensionCommandContext): Promise<string | null> {
  const messages = getHandoffMessages(ctx.sessionManager.getBranch());
  if (messages.length === 0) {
    ctx.ui.notify("No conversation to hand off", "error");
    return null;
  }

  const conversationText = serializeConversation(convertToLlm(messages));

  return ctx.ui.custom<string | null>((tui, theme, _kb, done) => {
    const loader = new BorderedLoader(tui, theme, `Generating Trailboss ${mode} prompt...`);
    loader.onAbort = () => done(null);

    const doGenerate = async () => {
      const auth = await ctx.modelRegistry.getApiKeyAndHeaders(ctx.model!);
      if (!auth.ok || !auth.apiKey) {
        throw new Error(auth.ok ? `No API key for ${ctx.model!.provider}` : auth.error);
      }

      const userMessage: Message = {
        role: "user",
        content: [
          {
            type: "text",
            text: `## Conversation History\n\n${conversationText}\n\n## Trailboss Mode\n\n${mode}\n\n## User's Goal for Trailboss\n\n${goal}`,
          },
        ],
        timestamp: Date.now(),
      };

      const response = await complete(
        ctx.model!,
        { systemPrompt: SYSTEM_PROMPT, messages: [userMessage] },
        { apiKey: auth.apiKey, headers: auth.headers, signal: loader.signal, maxTokens: 2048 },
      );

      if (response.stopReason === "aborted") return null;

      return response.content
        .filter((c): c is { type: "text"; text: string } => c.type === "text")
        .map((c) => c.text)
        .join("\n")
        .trim();
    };

    doGenerate()
      .then(done)
      .catch((err) => {
        console.error("Trailboss handoff generation failed:", err);
        done(null);
      });

    return loader;
  });
}

function registerTrailbossCommand(pi: ExtensionAPI, name: string, mode: TrailbossMode | null) {
  pi.registerCommand(name, {
    description: mode
      ? `Generate current-context handoff and run trailboss ${mode}`
      : "Generate current-context handoff and run trailboss act|ask",
    handler: async (args, ctx) => {
      if (!ctx.hasUI) {
        ctx.ui.notify("trailboss handoff requires interactive mode", "error");
        return;
      }
      if (!ctx.model) {
        ctx.ui.notify("No model selected", "error");
        return;
      }

      const parsed = mode ? { mode, goal: args.trim() } : parseTrailbossArgs(args);
      if (!parsed?.goal) {
        const usage = mode ? `/${name} <goal>` : `/${name} <act|ask> <goal>`;
        ctx.ui.notify(`Usage: ${usage}`, "error");
        return;
      }

      const generated = await generatePrompt(parsed.mode, parsed.goal, ctx);
      if (generated === null) {
        ctx.ui.notify("Cancelled", "info");
        return;
      }

      const edited = await ctx.ui.editor(`Edit Trailboss ${parsed.mode} prompt`, generated);
      if (edited === undefined) {
        ctx.ui.notify("Cancelled", "info");
        return;
      }

      const result = await pi.exec("trailboss", [parsed.mode, edited], { cwd: ctx.cwd, timeout: 30_000 });
      if (result.code === 0) {
        const detail = (result.stdout || result.stderr).trim();
        ctx.ui.notify(detail ? `trailboss ${parsed.mode} queued: ${detail}` : `trailboss ${parsed.mode} queued`, "info");
      } else {
        ctx.ui.notify(`trailboss ${parsed.mode} failed (${result.code}): ${(result.stderr || result.stdout).trim()}`, "error");
      }
    },
  });
}

export default function trailbossHandoff(pi: ExtensionAPI) {
  registerTrailbossCommand(pi, "trailboss", null);
  registerTrailbossCommand(pi, "tb-act", "act");
  registerTrailbossCommand(pi, "tb-ask", "ask");
  registerTrailbossCommand(pi, "tbact", "act");
  registerTrailbossCommand(pi, "tbask", "ask");
}
