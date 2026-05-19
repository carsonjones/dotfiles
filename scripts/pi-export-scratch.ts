import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { exec } from "node:child_process";
import { promisify } from "node:util";
import { resolve } from "node:path";
import { existsSync, mkdirSync } from "node:fs";

const execAsync = promisify(exec);

export default function (pi: ExtensionAPI) {
  pi.registerCommand("xs", {
    description: "Export session to scratch folder with timestamp",
    handler: async (args, ctx) => {
      const sessionFile = ctx.sessionManager.getSessionFile();
      if (!sessionFile) {
        ctx.ui.notify("Cannot export an unsaved session.", "error");
        return;
      }

      const now = new Date();
      const year = now.getFullYear();
      const month = String(now.getMonth() + 1).padStart(2, "0");
      const day = String(now.getDate()).padStart(2, "0");
      const hours = String(now.getHours()).padStart(2, "0");
      const mins = String(now.getMinutes()).padStart(2, "0");
       
      const filename = `${year}-${month}-${day}-${hours}${mins}-pi-session.html`;
      const outputDir = resolve(process.env.HOME || "", "main/scratch");
      
      if (!existsSync(outputDir)) {
         mkdirSync(outputDir, { recursive: true });
      }
      
      const outputPath = resolve(outputDir, filename);

      try {
        ctx.ui.setStatus("xs", "Exporting to scratch...");
        
        // Execute the pi CLI to perform the export in a headless manner
        await execAsync(`pi --export "${sessionFile}" "${outputPath}"`);
        
        ctx.ui.setStatus("xs", undefined);
        ctx.ui.notify(`Exported to ${outputPath}`, "success");
      } catch (err) {
        ctx.ui.setStatus("xs", undefined);
        ctx.ui.notify(`Export failed: ${err instanceof Error ? err.message : String(err)}`, "error");
      }
    }
  });
}
