import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent/extensibility/extensions/types";
import morphPlugin from "../upstream/oh-my-pi-plugin-morph/src/index.ts";
import { codexAccess } from "../src/codex-auth.ts";
import { workerModels, workerModel, delegationPolicy } from "../src/chat-routing.ts";
import { OpenRouterJevProvider, requestSchema } from "../src/decisions.ts";
import { inspect } from "../src/evidence.ts";
import { findRelevantCode } from "../src/workflow.ts";
import { warpCandidates } from "../src/specialists.ts";
export default async function chat(pi: ExtensionAPI) {
  pi.registerProvider("openai-codex", { apiKey: await codexAccess() });
  pi.registerProvider("morph-lab", {
    baseUrl: "https://api.morphllm.com/v1", api: "openai-completions", apiKey: "MORPH_API_KEY",
    models: [...new Set(Object.values(workerModels))].map(id => ({ id, name: id,
      reasoning: false, input: ["text"], contextWindow: 128000, maxTokens: 8192,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, compat: { supportsDeveloperRole: false, maxTokensField: "max_tokens", supportsStore: false } })),
  });
  await morphPlugin(pi);
  pi.on("before_subagent_spawn", async event => ({ model: workerModel(event.agent), note: "Morph worker assignment" }));
  pi.on("before_agent_start", async (event, ctx) => {
    if (ctx.agent.kind === "sub") pi.setActiveTools(pi.getActiveTools().filter(name => name !== "task"));
    return { systemPrompt: [...event.systemPrompt, ctx.agent.kind === "main" ? delegationPolicy : "Complete your bounded assignment directly. Do not delegate further. Use the available Morph specialists and preserve uncertainty."] };
  });
  const { z } = pi.zod;
  const text = () => z.string().min(1).max(2000);
  const typedQuestion = z.union([
    z.object({ type: z.literal("noul"), instructions: text(), criteria: z.object({ true: text().optional(), false: text().optional() }).optional() }),
    z.object({ type: z.literal("choice"), instructions: text(), criteria: z.record(z.string(), text()) }),
    z.object({ type: z.literal("score"), instructions: text(), criteria: z.array(text()).min(2).max(10) }),
  ]);
  const decision = new OpenRouterJevProvider(process.env.OPENROUTER_API_KEY);
  pi.registerTool({ name: "jev_judge", label: "Jev bounded decision", description: "Typed bounded questions over supplied non-secret evidence. Returns probabilities; failure never triggers model substitution.",
    parameters: z.object({ state: z.string().min(1).max(24000), scope: z.string().optional(), questions: z.record(z.string(), typedQuestion) }), async execute(_id, params) {
      return { content: [{ type: "text", text: JSON.stringify(await decision.judge(requestSchema.parse(params))) }] };
    } });
  pi.registerTool({ name: "find_relevant_code", label: "Bounded code localization", description: "FindRelevantCode: deterministic native search plus Jev decisions and optional WarpGrep. Never launches a fallback agent.",
    parameters: pi.zod.z.object({ task: pi.zod.z.string().min(1).max(4000) }),
    async execute(_id, params, _signal, _update, ctx) {
      return { content: [{ type: "text", text: JSON.stringify(await findRelevantCode((params as { task: string }).task, ctx.cwd,
        { decision, inspect, warpGrep: warpCandidates }, { allowFallback: false })) }] };
    } });
  pi.registerCommand("morph-status", { description: "Show configured Morph worker roles", handler: async (_args, ctx) => {
    ctx.ui.notify("Sol medium · Codex subscription · Jev via OpenRouter · " + JSON.stringify(workerModels) + " · 32 workers / depth 2. Displayed Morph cost is unavailable (zero placeholder).", "info");
  } });
}
