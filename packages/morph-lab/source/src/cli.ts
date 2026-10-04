import { loadMorphKey, loadOpenRouterKey } from "./key.ts";
import { MorphSystemOneProvider, OpenRouterJevProvider } from "./decisions.ts";
import { inspect } from "./evidence.ts";
import { findRelevantCode } from "./workflow.ts";
const args = process.argv.slice(2);
if (args.includes("--help") || !args.length) {
  console.log(
    "Usage: morph-lab [--no-agent] [--repo PATH] TASK\nOnly FindRelevantCode is bounded; confidently unsupported tasks may delegate once to Morph-enabled Pi.",
  );
  process.exit(0);
}
const noAgent = args.includes("--no-agent");
const repoIndex = args.indexOf("--repo");
const repo =
  repoIndex >= 0
    ? args[repoIndex + 1]
    : (process.env.MORPH_LAB_DEFAULT_REPO ?? process.cwd());
if (repoIndex >= 0) args.splice(repoIndex, 2);
const task = args.filter((a) => a !== "--no-agent").join(" ");
const provider = process.env.MORPH_LAB_DECISION_PROVIDER ?? "morph";
if (!["morph", "jev"].includes(provider))
  throw Error("Decision provider must be morph or jev");
const key = await loadMorphKey();
const openRouterKey =
  provider === "jev" ? await loadOpenRouterKey() : undefined;
if (provider === "jev" ? !openRouterKey : !key) {
  console.log(
    JSON.stringify({
      status: "not_checked",
      reason: `${provider === "jev" ? "OPENROUTER_API_KEY" : "MORPH_API_KEY"} missing`,
      notChecked: ["No remote decisions or specialists called"],
    }),
  );
  process.exit(2);
}
const { warpCandidates } = await import("./specialists.ts");
const { piFallback } = await import("./pi-fallback.ts");
const result = await findRelevantCode(
  task,
  repo,
  {
    decision:
      provider === "jev"
        ? new OpenRouterJevProvider(openRouterKey)
        : new MorphSystemOneProvider(key),
    inspect,
    warpGrep: warpCandidates,
    fallback: piFallback,
  },
  { allowFallback: !noAgent, nested: process.env.MORPH_LAB_NESTED === "1" },
);
let output = JSON.stringify(result, null, 2);
for (const credential of [key, openRouterKey])
  if (credential) output = output.replaceAll(credential, "[REDACTED]");
console.log(output);
process.exitCode =
  result.status === "provider_failure"
    ? 1
    : result.status === "handled" ||
        (result.status === "agent_fallback" &&
          result.agent?.outcome === "finished")
      ? 0
      : 2;
