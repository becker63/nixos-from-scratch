import {
  MORPH_API_KEY,
  MORPH_EDIT_ENABLED,
  MORPH_FASTCOMPACT_ENABLED,
  MORPH_ROUTING_HINT_HEADER,
  MORPH_WARPGREP_ENABLED,
  MORPH_WARPGREP_GITHUB_ENABLED,
} from "./config.js";

function appendRuntimeNotes(description: string, notes: string[]): string {
  if (notes.length === 0) return description;

  return `${description}\n\nRuntime notes:\n${notes.map((note) => `- ${note}`).join("\n")}`;
}

export function buildToolNote(toolID: string): string {
  const notes: string[] = [];

  switch (toolID) {
    case "fast_edit":
      notes.push("Relative paths resolve from the active session directory.");
      break;
    case "codebase_warpsearch":
      notes.push("Searches the current project worktree, not just the immediate cwd.");
      break;
    case "github_warpsearch":
      notes.push("Use this for public GitHub source questions, not the current checked-out repo.");
      break;
    case "fastcompact":
      notes.push("Compacts supplied file or artifact locations into text; it does not compact the conversation.");
      break;
    default:
      break;
  }

  if (notes.length > 0 && !MORPH_API_KEY) {
    notes.push("Currently unavailable until MORPH_API_KEY is configured.");
  }

  return appendRuntimeNotes("", notes).trim();
}

export function withToolNote(description: string, toolID: string): string {
  const note = buildToolNote(toolID);
  return note ? `${description}\n\n${note}` : description;
}

export function buildMorphSystemRoutingHint(): string | null {
  if (!MORPH_API_KEY) {
    return [
      MORPH_ROUTING_HINT_HEADER,
      "- Morph remote tools are currently unavailable because MORPH_API_KEY is not configured.",
      "- Use native edit/write/grep tools until Morph credentials are configured.",
    ].join("\n");
  }

  const toolLines: string[] = [];

  if (MORPH_EDIT_ENABLED) {
    toolLines.push(
      "- Prefer fast_edit for edits inside existing files, especially large, scattered, or whitespace-sensitive changes.",
    );
    toolLines.push(
      "- Native edit still wins for trivial single-line or exact-string replacements; native write creates brand-new files.",
    );
  }

  if (MORPH_WARPGREP_ENABLED) {
    toolLines.push(
      "- Prefer codebase_warpsearch over manual grep-and-read loops for exploratory or natural-language questions about the workspace; native search is for exact symbol or string lookups.",
    );
  }

  if (MORPH_WARPGREP_GITHUB_ENABLED) {
    toolLines.push(
      "- Prefer github_warpsearch over web search or doc fetching for how a public library or SDK works internally.",
    );
  }

  if (MORPH_FASTCOMPACT_ENABLED) {
    toolLines.push(
      "- Prefer fastcompact to condense a specific file or artifact into focused text before reading it in full; it does not compact the conversation.",
    );
  }

  if (toolLines.length === 0) return null;

  return [
    MORPH_ROUTING_HINT_HEADER,
    "- Favor Morph-backed tools over their native equivalents whenever the task fits one.",
    ...toolLines,
  ].join("\n");
}
