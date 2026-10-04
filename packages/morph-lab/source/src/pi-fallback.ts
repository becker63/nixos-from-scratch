import { openPluginSession } from "../scripts/plugin-host.ts";
import { safePath, inspect, publicMirror } from "./evidence.ts";
import { metrics, type AgentResult } from "./workflow.ts";
import type { ExtensionFactory } from "@oh-my-pi/pi-coding-agent";
import { makeWarpgrepCodebase } from "../upstream/oh-my-pi-plugin-morph/src/tools/warpgrep.ts";
/** Native replacement, native new file, Morph materialization for scattered existing-file edits. */
export function materializationTool(
  kind: "new_file" | "tiny_exact" | "scattered_existing",
) {
  return kind === "new_file"
    ? "write"
    : kind === "tiny_exact"
      ? "edit"
      : "fast_edit";
}
export async function piFallback(
  task: string,
  repo: string,
): Promise<AgentResult> {
  const counts = metrics(),
    tools: string[] = [];
  let budget = false;
  const guard: ExtensionFactory = (pi) => {
    // Same upstream search tool, over an explicit source-only mirror.
    const semantic = makeWarpgrepCodebase(pi);
    pi.registerTool({
      ...semantic,
      async execute(id, params, signal, onUpdate, ctx) {
        const evidence = await inspect("", repo),
          mirror = await publicMirror(repo, evidence.files);
        try {
          const result = await semantic.execute(id, params, signal, onUpdate, {
            ...ctx,
            cwd: mirror.root,
          });
          return {
            ...result,
            content: result.content.map((part) =>
              part.type === "text"
                ? { ...part, text: part.text.replaceAll(mirror.root, repo) }
                : part,
            ),
          };
        } finally {
          await mirror.dispose();
        }
      },
    });
    pi.on("tool_call", async (event) => {
      if (tools.length >= 12) {
        budget = true;
        return { block: true, reason: "Tool budget exhausted" };
      }
      if (event.toolName === "codebase_warpsearch") return;
      const input = event.input as Record<string, unknown>;
      const paths =
        event.toolName === "fastcompact"
          ? (input.locations ?? [input.location])
          : [input.path ?? input.target_filepath];
      if (!Array.isArray(paths) || paths.length < 1)
        return { block: true, reason: "Explicit file paths required" };
      try {
        for (const path of paths) {
          if (
            typeof path !== "string" ||
            path.includes("://") ||
            /[\n;,]/.test(path)
          )
            throw Error();
          await safePath(repo, path.replace(/:\d+(?:-\d+)?$/, ""));
        }
      } catch {
        return { block: true, reason: "Unsafe or secret file path refused" };
      }
    });
  };
  const session = await openPluginSession(
    repo,
    [
      "read",
      "edit",
      "write",
      "codebase_warpsearch",
      "fast_edit",
      "fastcompact",
    ],
    [guard],
  );
  const stream = session.agent.streamFn;
  session.agent.streamFn = (model, context, options) => {
    if (counts.generalModelCalls >= 6) {
      budget = true;
      throw Error("General model call budget exhausted");
    }
    counts.generalModelCalls++;
    return stream(model, context, options);
  };
  const timer = setTimeout(() => {
    budget = true;
    void session.abort();
  }, 90000);
  const unsubscribe = session.subscribe((event) => {
    if (event.type === "tool_execution_start") {
      tools.push(event.toolName);
      if (event.toolName === "codebase_warpsearch") counts.warpGrepCalls++;
      if (event.toolName === "fast_edit") counts.fastApplyCalls++;
      if (event.toolName === "fastcompact") counts.compactCalls++;
      if (tools.length > 12) {
        budget = true;
        void session.abort();
      }
    }
  });
  try {
    await session.prompt(
      `Complete this coding task in the current repository. No commits, pushes, publication, credential access, delegation or recursive harness calls. Use the smallest suitable tools. The only available tools are local reads, native exact edits/new file writes, and Morph specialists. Budget: 6 model turns, 12 tools, 90 seconds. Report uncertainty and do not claim tests ran unless provided exact results.\nTask:\n${task}`,
    );
    const last = [...session.agent.state.messages]
      .reverse()
      .find((x) => x.role === "assistant");
    const text =
      last && "content" in last && Array.isArray(last.content)
        ? last.content
            .filter((p) => p.type === "text")
            .map((p) => (p.type === "text" ? p.text : ""))
            .join("\n")
        : "";
    const error =
      last &&
      "stopReason" in last &&
      (last.stopReason === "error" || last.stopReason === "aborted");
    return {
      outcome: budget ? "budget" : error || !text ? "failed" : "finished",
      text,
      counts,
      tools,
    };
  } catch (error) {
    const detail = String(error)
      .replaceAll(process.env.MORPH_API_KEY ?? "__absent__", "[REDACTED]")
      .slice(0, 300);
    return {
      outcome: budget ? "budget" : "failed",
      text: `Pi provider failure: ${detail}`,
      counts,
      tools,
    };
  } finally {
    clearTimeout(timer);
    unsubscribe();
    await session.dispose();
  }
}
