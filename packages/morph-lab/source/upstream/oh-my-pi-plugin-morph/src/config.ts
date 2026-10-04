export const PLUGIN_PACKAGE_NAME = "oh-my-pi-plugin-morph";

export let MORPH_API_KEY = process.env.MORPH_API_KEY;

export function setMorphApiKey(apiKey: string | undefined): void {
  MORPH_API_KEY = apiKey;
}

export const MORPH_API_URL = "https://api.morphllm.com";
export const MORPH_TIMEOUT = 30_000;
export const MORPH_WARP_GREP_TIMEOUT = 60_000;
export const MORPH_COMPACT_TIMEOUT = 60_000;
// OMP caps session_before_compact extension handlers at 30s
// (EXTENSION_HANDLER_TIMEOUT_MS). Self-abort just under that ceiling so a
// slow Morph compact call falls back to native compaction here instead of
// being killed by the host and orphaning the in-flight HTTP request.
// Separate from MORPH_COMPACT_TIMEOUT (the SDK client / fastcompact budget)
// because fastcompact is a tool, not a session_before_compact handler, and
// legitimately needs the full 60s.
export const MORPH_HANDLER_BUDGET_MS = 28_000;
export const GITHUB_RESOLVER_TIMEOUT = 10_000;
export const GITHUB_REPO_API_URL = "https://api.github.com/repos";
export const GITHUB_REPO_SEARCH_URL = "https://api.github.com/search/repositories";
export const GITHUB_REPO_SUGGESTION_LIMIT = 5;

export const EXISTING_CODE_MARKER = "// ... existing code ...";
export const MORPH_ROUTING_HINT_HEADER = "Morph plugin routing hints:";
export const PLUGIN_VERSION = "0.6.0";

export type MorphFastEditModel = "auto" | "morph-v3-fast" | "morph-v3-large";
export const DEFAULT_MORPH_FAST_EDIT_MODEL: MorphFastEditModel = "auto";

export let COMPACT_RATIO = compactRatioFrom(process.env.MORPH_COMPACT_RATIO);
export let MORPH_FAST_EDIT_MODEL = fastEditModelFrom(process.env.MORPH_EDIT_MODEL);

export let MORPH_EDIT_ENABLED = booleanFrom(process.env.MORPH_EDIT, true);
export let MORPH_WARPGREP_ENABLED = booleanFrom(process.env.MORPH_WARPGREP, false);
export let MORPH_WARPGREP_GITHUB_ENABLED = booleanFrom(
  process.env.MORPH_WARPGREP_GITHUB,
  false,
);
export let MORPH_COMPACT_ENABLED = booleanFrom(process.env.MORPH_COMPACT, true);
export let MORPH_FASTCOMPACT_ENABLED = booleanFrom(process.env.MORPH_FASTCOMPACT, true);
export let MORPH_ROUTING_HINT_ENABLED = booleanFrom(
  process.env.MORPH_ROUTING_HINT,
  true,
);

export function applyMorphSettings(settings: Record<string, unknown> = {}): void {
  const apiKey = stringSetting(settings, "apiKey");
  MORPH_API_KEY = apiKey ?? process.env.MORPH_API_KEY;
  COMPACT_RATIO = compactRatioFrom(
    numberSetting(settings, "compactRatio") ?? process.env.MORPH_COMPACT_RATIO,
  );
  MORPH_FAST_EDIT_MODEL = fastEditModelFrom(
    stringSetting(settings, "editModel") ?? process.env.MORPH_EDIT_MODEL,
  );
  MORPH_EDIT_ENABLED = booleanSetting(settings, "editEnabled", "MORPH_EDIT", true);
  MORPH_WARPGREP_ENABLED = booleanSetting(
    settings,
    "warpgrepEnabled",
    "MORPH_WARPGREP",
    false,
  );
  MORPH_WARPGREP_GITHUB_ENABLED = booleanSetting(
    settings,
    "warpgrepGithubEnabled",
    "MORPH_WARPGREP_GITHUB",
    false,
  );
  MORPH_COMPACT_ENABLED = booleanSetting(settings, "compactEnabled", "MORPH_COMPACT", true);
  MORPH_FASTCOMPACT_ENABLED = booleanSetting(
    settings,
    "fastcompactEnabled",
    "MORPH_FASTCOMPACT",
    true,
  );
  MORPH_ROUTING_HINT_ENABLED = booleanSetting(
    settings,
    "routingHintEnabled",
    "MORPH_ROUTING_HINT",
    true,
  );
}

function stringSetting(settings: Record<string, unknown>, key: string): string | undefined {
  const value = settings[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

export function setMorphFastEditModel(model: string | undefined): void {
  MORPH_FAST_EDIT_MODEL = fastEditModelFrom(model);
}

function fastEditModelFrom(value: string | undefined): MorphFastEditModel {
  const normalized = value?.trim();
  switch (normalized) {
    case "auto":
    case "morph-v3-fast":
    case "morph-v3-large":
      return normalized;
    default:
      return DEFAULT_MORPH_FAST_EDIT_MODEL;
  }
}

function numberSetting(settings: Record<string, unknown>, key: string): number | undefined {
  const value = settings[key];
  return typeof value === "number" ? value : undefined;
}

function booleanSetting(
  settings: Record<string, unknown>,
  key: string,
  envName: string,
  defaultValue: boolean,
): boolean {
  const value = settings[key];
  return typeof value === "boolean"
    ? value
    : booleanFrom(process.env[envName], defaultValue);
}

function booleanFrom(value: string | undefined, defaultValue: boolean): boolean {
  if (value === undefined) return defaultValue;
  const normalized = value.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  return defaultValue;
}

function compactRatioFrom(value: string | number | undefined): number {
  const parsed =
    typeof value === "number" ? value : Number.parseFloat(value || "0.2");
  return Number.isFinite(parsed) && parsed >= 0.05 && parsed <= 1 ? parsed : 0.2;
}

// Upper bound on the bytes of a single resolved fastcompact input (file or
// artifact) checked before any Morph API call, and the maximum number of
// locations one fastcompact call may target. Both gate the SDK call so a single
// tool call cannot stream an unbounded payload to Morph.
export const FASTCOMPACT_MAX_BYTES = 1_048_576;
export const FASTCOMPACT_MAX_LOCATIONS = 10;

// Upper bound on the UTF-8 byte length of the optional fastcompact focus query,
// checked before any Morph API call so a single tool call cannot smuggle an
// unbounded query string to Morph alongside the bounded input.
export const FASTCOMPACT_MAX_QUERY_BYTES = 16_384;
