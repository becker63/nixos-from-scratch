import { relative } from "node:path";
import { safePath, publicMirror, type Candidate } from "./evidence.ts";
import { openPluginSession } from "../scripts/plugin-host.ts";
export interface SpecialistTools {
  run(
    name: "codebase_warpsearch" | "fast_edit" | "fastcompact",
    repo: string,
    params: Record<string, unknown>,
  ): Promise<{ text: string; updates: string[] }>;
}
export function toolText(result: any): string {
  return result.content
    .filter((p: any) => p.type === "text")
    .map((p: any) => p.text)
    .join("\n");
}
/** Reuse registered Pi plugin tools, including upstream retry and result guards. */
export class PiMorphTools implements SpecialistTools {
  async run(
    name: "codebase_warpsearch" | "fast_edit" | "fastcompact",
    repo: string,
    params: Record<string, unknown>,
  ) {
    if (name === "fastcompact") {
      const paths = params.locations ?? [params.location];
      if (!Array.isArray(paths) || !paths.length)
        throw Error("Explicit files required");
      for (const path of paths) {
        if (typeof path !== "string" || path.startsWith("artifact://"))
          throw Error("Untrusted artifact locator refused");
        await safePath(repo, path);
      }
    }
    if (name === "fast_edit")
      await safePath(repo, String(params.target_filepath ?? ""));
    const session = await openPluginSession(repo);
    try {
      const tool = session.agent.state.tools.find((t) => t.name === name);
      if (!tool) throw Error("Specialist unavailable");
      const updates: string[] = [];
      const result = await tool.execute(
        "lab",
        params,
        AbortSignal.timeout(70000),
        (u) => updates.push(toolText(u)),
      );
      const text = toolText(result);
      if (
        result.isError ||
        /^(?:Error|Search failed|WarpGrep search failed|Morph fast_edit failed)/.test(
          text,
        )
      )
        throw Error("Specialist provider failure");
      return { text, updates };
    } finally {
      await session.dispose();
    }
  }
}
function unescape(s: string) {
  return s
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}
export async function warpCandidates(
  task: string,
  repo: string,
  files: string[],
  tools: SpecialistTools = new PiMorphTools(),
): Promise<Candidate[]> {
  const mirror = await publicMirror(repo, files);
  try {
    const { text } = await tools.run("codebase_warpsearch", mirror.root, {
      search_term: task,
    });
    const candidates: Candidate[] = [];
    for (const match of text.matchAll(
      /<file path="([^"]+)"[^>]*>([\s\S]*?)<\/file>/g,
    )) {
      const full = unescape(match[1]);
      const path = full.startsWith("/") ? relative(mirror.root, full) : full;
      if (!files.includes(path)) continue;
      await safePath(repo, path);
      // Format lines carries ranges; fallback to content length if absent.
      const tag = match[0].slice(0, match[0].indexOf(">") + 1);
      const span = tag.match(/(?:lines|range)="(\d+)-(\d+)"/);
      const content = unescape(match[2]).replace(/^\n/, "").slice(0, 4000);
      if (!content.trim()) continue;
      candidates.push({
        id: "",
        path,
        start: span ? Number(span[1]) : 1,
        end: span ? Number(span[2]) : content.split("\n").length,
        text: content,
        source: "warpgrep",
      });
    }
    return candidates.slice(0, 3);
  } finally {
    await mirror.dispose();
  }
}
