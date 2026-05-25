// Quit pi with vim-style commands: :q, :quit, :wq, :x
// Type import omitted intentionally — pi loads this via jiti at runtime
// and the `@earendil-works/pi-coding-agent` package isn't installed for
// editor LSP. The extension API shape we use is stable.

/** @param {import("@earendil-works/pi-coding-agent").ExtensionAPI} pi */
export default function (pi: any) {
  pi.on("input", async (event: any, ctx: any) => {
    const t = event.text.trim();
    if (t === ":q" || t === ":quit" || t === ":wq" || t === ":x") {
      ctx.ui.notify("Bye 👋", "info");
      ctx.shutdown();
      return { action: "handled" };
    }
  });
}
