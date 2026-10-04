import type { Static } from "@oh-my-pi/pi-ai/types";
import type { Stats } from "node:fs";
import { stat } from "node:fs/promises";
import type {
  AgentToolResult,
  AgentToolUpdateCallback,
  ExtensionAPI,
  ExtensionContext,
  ToolDefinition,
} from "@oh-my-pi/pi-coding-agent/extensibility/extensions/types";
import type { CompactResult } from "@morphllm/morphsdk";
import { throwIfAborted, ToolAbortError } from "@oh-my-pi/pi-coding-agent/tools/tool-errors";
import {
  COMPACT_RATIO,
  FASTCOMPACT_MAX_BYTES,
  FASTCOMPACT_MAX_LOCATIONS,
  FASTCOMPACT_MAX_QUERY_BYTES,
  MORPH_API_KEY,
  MORPH_COMPACT_TIMEOUT,
} from "../config.js";
import { compactResultText, textToolResult } from "../compaction.js";
import { resolveReadPath } from "../format.js";
import { compactClient } from "../morph-clients.js";
import { withToolNote } from "../routing.js";
import { raceAbort } from "../abort.js";
import { nextMorphRetryDelay, transientMorphFailureMessage, waitForMorphRetry } from "../retry.js";

const ARTIFACT_PREFIX = "artifact://";

// Conventional glob metacharacters. A location must name one concrete file;
// any of these means the caller passed a pattern, which would either silently
// match nothing or, worse, smuggle multiple paths past the single-file
// preflight checks. Reject before resolving.
const GLOB_RE = /[*?[\]{}]/;

const DESCRIPTION = `Compact one or more file or artifact locations into a shorter, query-focused digest using Morph Compact, and return the compacted text only.

WHEN TO USE fastcompact:
- Prefer this over reading a large file or long artifact in full when you only need a focused digest before reasoning over it
- Produce a focused summary of supplied content via an optional 'query'

INPUT MODES (pass exactly one of 'location' or 'locations' and omit the other field entirely; a blank string or empty array is treated as omitted):
- location: a single file path or an "artifact://<id>" locator
- locations: an array of such locators, compacted in order with labeled sections
- query: optional focus to condition the compaction
- compression_ratio: optional fraction of content to keep (0.05-1.0)

GUARANTEES:
- Read-only: never writes to disk, overwrites inputs, saves artifacts, or mutates session history
- Returns compacted text only; it does NOT compact the conversation (manual /compact and the session compaction hook handle that)

LIMITS: no directories, globs, or secret files (case-sensitive basename match: .env and .env.*, private keys, credential configs); bounded input size and location count. Absolute and out-of-tree paths are allowed.

FALLBACK: If fastcompact is unavailable (no MORPH_API_KEY) or fails, read the location with the native 'read' tool.`;

// A resolved location is either readable text or a preflight error message.
// Resolution never calls Morph, so any failure here short-circuits before the
// SDK is touched.
type ResolvedLocation = { text: string } | { error: string };

// Read a concrete file at an already-trusted absolute path, enforcing the
// directory, size, and emptiness preflight bounds. `label` names the original
// locator for clear error messages.
async function readBoundedFile(absPath: string, label: string): Promise<ResolvedLocation> {
  let info: Stats;
  try {
    info = await stat(absPath);
  } catch {
    return { error: `Location not found: ${label}` };
  }
  if (info.isDirectory()) {
    return { error: `Location is a directory, not a file: ${label}` };
  }
  if (info.size > FASTCOMPACT_MAX_BYTES) {
    return {
      error: `Location too large: ${label} is ${info.size} bytes (limit ${FASTCOMPACT_MAX_BYTES}). Narrow the input before compacting.`,
    };
  }
  // Read at most FASTCOMPACT_MAX_BYTES + 1 through one sliced handle so a file
  // grown or swapped between the stat above and this read cannot push an
  // oversized payload into memory or on to Morph past the bound.
  const text = await Bun.file(absPath).slice(0, FASTCOMPACT_MAX_BYTES + 1).text();
  if (Buffer.byteLength(text, "utf8") > FASTCOMPACT_MAX_BYTES) {
    return {
      error: `Location too large: ${label} exceeds ${FASTCOMPACT_MAX_BYTES} bytes (changed during read). Narrow the input before compacting.`,
    };
  }
  if (!text.trim()) {
    return { error: `Location has no content to compact: ${label}` };
  }
  return { text };
}

// Resolve a single locator to readable text without ever calling Morph.
// Artifact locators go through the session manager; everything else is treated
// as a file path: secret files are refused and in-tree symlink escapes are
// blocked, but absolute and out-of-tree reads are allowed.
async function resolveLocation(
  location: string,
  ctx: ExtensionContext,
  signal: AbortSignal | undefined,
): Promise<ResolvedLocation> {
  const trimmed = location.trim();
  if (!trimmed) {
    return { error: "Empty location: provide a file path or artifact://<id>." };
  }

  if (trimmed.startsWith(ARTIFACT_PREFIX)) {
    const id = trimmed.slice(ARTIFACT_PREFIX.length).trim();
    if (!id) {
      return { error: `Invalid artifact locator: ${location} (missing id).` };
    }
    const artifactPath = await ctx.sessionManager.getArtifactPath(id);
    throwIfAborted(signal);
    if (!artifactPath) {
      return { error: `Unknown artifact: ${trimmed}` };
    }
    return readBoundedFile(artifactPath, trimmed);
  }

  if (GLOB_RE.test(trimmed)) {
    return { error: `Globs are not allowed: ${location}. Pass one concrete file path.` };
  }

  let resolved: string;
  try {
    resolved = resolveReadPath(trimmed, ctx.cwd);
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
  return readBoundedFile(resolved, trimmed);
}

export function makeFastCompact(pi: ExtensionAPI) {
  const { z } = pi.zod;
  const parameters = z.object({
    location: z
      .string()
      .optional()
      .describe('A single file path or "artifact://<id>" locator to compact. Exactly one of location/locations must be provided; omit this field entirely when using locations.'),
    locations: z
      .array(z.string())
      .optional()
      .describe('Multiple file paths or "artifact://<id>" locators, compacted in order with labeled sections. Exactly one of location/locations must be provided; omit this field entirely when using location.'),
    query: z
      .string()
      .optional()
      .describe("Optional focus query to condition the compaction on."),
    compression_ratio: z
      .number()
      .optional()
      .describe("Optional fraction of content to keep (0.05-1.0). Defaults to the configured ratio."),
  });

  return {
    name: "fastcompact",
    label: "Fast Compact",
    description: withToolNote(DESCRIPTION, "fastcompact"),
    parameters,
    approval: "read",
    async execute(
      _toolCallId: string,
      params: Static<typeof parameters>,
      signal: AbortSignal | undefined,
      _onUpdate: AgentToolUpdateCallback | undefined,
      ctx: ExtensionContext,
    ): Promise<AgentToolResult> {
      try {
        if (!MORPH_API_KEY || !compactClient) {
          return textToolResult(`Error: MORPH_API_KEY not configured.

To use fastcompact, set the MORPH_API_KEY environment variable.
Get your API key at: https://morphllm.com/dashboard/api-keys

Alternatively, read the location with the native 'read' tool.`, true);
        }
        const client = compactClient;

        // Blank 'location' and empty 'locations' name no locator. Some callers
        // serialize every schema field and send location: "" or locations: []
        // alongside the real input; treat both as omitted so they cannot trip
        // the either/or rejection below.
        const single = params.location?.trim() ? params.location : undefined;
        const multi = params.locations?.length ? params.locations : undefined;
        if (single !== undefined && multi !== undefined) {
          return textToolResult(
            "Error: pass either 'location' (single) or 'locations' (multiple), not both. Omit the unused field entirely; blank or empty values are ignored.",
            true,
          );
        }

        const list: string[] = single !== undefined ? [single] : multi ?? [];
        if (list.length === 0) {
          return textToolResult(
            params.locations !== undefined
              ? "Error: 'locations' must contain at least one entry."
              : "Error: provide 'location' for a single input or 'locations' for multiple inputs.",
            true,
          );
        }
        if (list.length > FASTCOMPACT_MAX_LOCATIONS) {
          return textToolResult(
            `Error: too many locations (${list.length}); the limit is ${FASTCOMPACT_MAX_LOCATIONS}.`,
            true,
          );
        }

        throwIfAborted(signal);

        // Preflight every location before any Morph call: a single bad locator
        // fails the whole call with no SDK request, so partial leakage cannot
        // happen on an otherwise-rejected input set.
        const resolved: string[] = [];
        for (const entry of list) {
          const outcome = await resolveLocation(entry, ctx, signal);
          if ("error" in outcome) {
            return textToolResult(outcome.error, true);
          }
          resolved.push(outcome.text);
        }

        // A provided compression_ratio must be a finite fraction in [0.05, 1].
        // Out-of-range or non-finite values are a caller error and must fail
        // before any Morph call rather than silently snapping to the default;
        // an omitted ratio still falls back to the configured COMPACT_RATIO.
        const rawRatio = params.compression_ratio;
        if (rawRatio !== undefined && (!Number.isFinite(rawRatio) || rawRatio < 0.05 || rawRatio > 1)) {
          return textToolResult(
            `Error: compression_ratio must be a finite number between 0.05 and 1.0 when provided (got ${rawRatio}).`,
            true,
          );
        }
        const compressionRatio = rawRatio ?? COMPACT_RATIO;
        const query = params.query?.trim() || undefined;
        // A focus query is sent to Morph alongside the bounded input; cap its
        // UTF-8 byte length here so an oversized query cannot smuggle an
        // unbounded payload past the input bound. Buffer.byteLength measures
        // without allocating the encoded query.
        if (query !== undefined) {
          const queryBytes = Buffer.byteLength(query, "utf8");
          if (queryBytes > FASTCOMPACT_MAX_QUERY_BYTES) {
            return textToolResult(
              `Error: query is too long (${queryBytes} bytes); the limit is ${FASTCOMPACT_MAX_QUERY_BYTES} bytes.`,
              true,
            );
          }
        }

        const sections: string[] = [];
        const startTime = Date.now();
        let attemptIndex = 0;
        for (const text of resolved) {
          let result: CompactResult;
          for (;;) {
            throwIfAborted(signal);
            try {
              // Race the in-flight Morph call against the abort signal so a cancel
              // mid-request rejects immediately instead of blocking on the remote
              // round-trip; raceAbort also drains the abandoned promise's rejection.
              result = await raceAbort(
                client.compact({
                  input: text,
                  query,
                  compressionRatio,
                  preserveRecent: 0,
                }),
                signal,
              );
            } catch (error) {
              const transientMessage = transientMorphFailureMessage(error);
              if (transientMessage === undefined) throw error;
              const delayMs = nextMorphRetryDelay(attemptIndex, startTime, MORPH_COMPACT_TIMEOUT);
              if (delayMs === undefined) throw error;
              pi.logger.warn(
                `fastcompact transient overload on attempt ${attemptIndex + 1}; retrying in ${delayMs}ms: ${transientMessage}`,
              );
              await waitForMorphRetry(delayMs, signal);
              attemptIndex++;
              continue;
            }
            break;
          }
          throwIfAborted(signal);
          sections.push(compactResultText(result));
        }

        if (single !== undefined) {
          return textToolResult(sections[0] ?? "");
        }

        const labeled = list
          .map((label, index) => `## ${label}\n${sections[index] ?? ""}`)
          .join("\n\n");
        return textToolResult(labeled);
      } catch (error) {
        if (
          error instanceof ToolAbortError ||
          (error instanceof Error && error.name === "AbortError") ||
          signal?.aborted
        ) {
          throw error instanceof Error ? error : new ToolAbortError();
        }
        const message = error instanceof Error ? error.message : String(error);
        return textToolResult(`fastcompact failed: ${message}`, true);
      }
    },
  } satisfies ToolDefinition<typeof parameters>;
}
