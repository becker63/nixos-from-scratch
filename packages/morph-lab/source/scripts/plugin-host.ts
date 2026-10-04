import { join } from "node:path";
import { homedir } from "node:os";
process.env.MORPH_WARPGREP = "true";
process.env.MORPH_WARPGREP_GITHUB = "true";
const { buildModel } = await import("@oh-my-pi/pi-catalog/build");
const { createAgentSession, SessionManager, Settings, AuthStorage } =
  await import("@oh-my-pi/pi-coding-agent");
const { default: morphPlugin } = await import(
  "../upstream/oh-my-pi-plugin-morph/src/index.ts"
);
export async function openPluginSession(
  cwd: string,
  names = [
    "fast_edit",
    "codebase_warpsearch",
    "github_warpsearch",
    "fastcompact",
  ],
  extraExtensions: import("@oh-my-pi/pi-coding-agent").ExtensionFactory[] = [],
) {
  const authStorage = await AuthStorage.create(":memory:");
  if (process.env.MORPH_API_KEY)
    authStorage.keys.setRuntime("morph-lab", process.env.MORPH_API_KEY);
  const { session } = await createAgentSession({
    cwd,
    agentDir: join(
      process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"),
      "morph-lab",
      "omp",
    ),
    model: buildModel({
      id: "morph-dsv41flash",
      name: "Morph Flash",
      provider: "morph-lab",
      api: "openai-completions",
      baseUrl: "https://api.morphllm.com/v1",
      compat: { supportsDeveloperRole: false },
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 128000,
      maxTokens: 4096,
    }),
    authStorage,
    getApiKey: async (model) =>
      model.provider === "morph-lab" &&
      model.baseUrl === "https://api.morphllm.com/v1"
        ? process.env.MORPH_API_KEY
        : undefined,
    settings: Settings.isolated({
      "retry.enabled": false,
      "retry.modelFallback": false,
      "compaction.enabled": true,
      "edit.mode": "replace",
    }),
    sessionManager: SessionManager.inMemory(cwd),
    extensions: [morphPlugin, ...extraExtensions],
    preloadedExtensionPaths: [],
    preloadedCustomToolPaths: [],
    toolNames: names,
    restrictToolNames: false,
    skills: [],
    rules: [],
    contextFiles: [],
    promptTemplates: [],
    slashCommands: [],
    enableMCP: false,
    enableLsp: false,
    enableIrc: false,
    skipPythonPreflight: true,
    autoApprove: true,
    spawns: "",
  });
  const dispose = session.dispose.bind(session);
  session.dispose = async (options) => {
    try {
      await dispose(options);
    } finally {
      authStorage.close();
    }
  };
  return session;
}
