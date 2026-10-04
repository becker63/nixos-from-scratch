import { mkdir, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadMorphKey, loadOpenRouterKey } from "./key.ts";
const state = process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state");
process.env.PI_CODING_AGENT_DIR ??= join(state, "morph-lab/chat");
process.env.PI_CONFIG_DIR ??= ".local/state/morph-lab/chat-config";
process.env.MORPH_LAB_ENV_FILE ??= join(homedir(), "nixos-from-scratch/.env");
await mkdir(process.env.PI_CODING_AGENT_DIR, { recursive: true, mode: 0o700 });
await writeFile(join(process.env.PI_CODING_AGENT_DIR, "settings.json"), JSON.stringify({
  modelRoles: { default: "openai-codex/gpt-6.1-sol", task: "morph-lab/morph-glm53flash", smol: "morph-lab/morph-dsv41flash", slow: "morph-lab/morph-glm53-744b", plan: "openai-codex/gpt-6.1-sol" },
  task: { batch: true, maxConcurrency: 32, maxRecursionDepth: 2, maxRuntimeMs: 300000 },
  retry: { modelFallback: false },
  startup: { setupWizard: false, showSplash: false, checkUpdate: false },
}), { flag: "wx", mode: 0o600 }).catch((e) => { if (e.code !== "EEXIST") throw e; });
await loadMorphKey();
await loadOpenRouterKey();
const { main } = await import("@oh-my-pi/pi-coding-agent");
await main(["launch", "--cwd", resolve(process.env.MORPH_LAB_DEFAULT_REPO ?? join(homedir(), "projects/attuneflix-tree-reuse")),
  "--provider", "openai-codex", "--model", "gpt-6.1-sol", "--thinking", "medium",
  "--config", fileURLToPath(new URL("../chat/defaults.yml", import.meta.url)),
  "--extension", fileURLToPath(new URL("../chat", import.meta.url)), ...process.argv.slice(2)]);
