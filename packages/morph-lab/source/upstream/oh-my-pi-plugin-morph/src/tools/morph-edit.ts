import type { ApplyEditInput, ApplyEditResult } from "@morphllm/morphsdk";
import { countChanges, generateUdiff } from "@morphllm/morphsdk/tools/fastapply";
import type { Static } from "@oh-my-pi/pi-ai/types";
import { unlink } from "node:fs/promises";
import { resolve } from "node:path";
import type {
  AgentToolResult,
  AgentToolUpdateCallback,
  ExtensionAPI,
  ExtensionContext,
  ToolDefinition,
} from "@oh-my-pi/pi-coding-agent/extensibility/extensions/types";
import { throwIfAborted, ToolAbortError } from "@oh-my-pi/pi-coding-agent/tools/tool-errors";
import { raceAbort } from "../abort.js";
import { MORPH_API_KEY, MORPH_API_URL, MORPH_FAST_EDIT_MODEL, MORPH_TIMEOUT, type MorphFastEditModel } from "../config.js";
import { textToolResult } from "../compaction.js";
import { nextMorphRetryDelay, transientMorphFailureMessage, waitForMorphRetry } from "../retry.js";
import {
  detectCatastrophicTruncation,
  detectMarkerLeakage,
  EXISTING_CODE_MARKER,
  normalizeCodeEditInput,
} from "../format.js";
import { morph } from "../morph-clients.js";
import { withToolNote } from "../routing.js";

const DESCRIPTION = `Edit existing files using partial code snippets with "// ... existing code ..." markers. Morph's AI merges your changes into the full file.

WHEN TO USE fast_edit vs edit:
- fast_edit [PREFERRED for in-file edits]: large files (300+ lines), multiple scattered changes, complex refactoring, whitespace-sensitive edits, or any edit where exact-string matching is fragile
- native edit: trivial single-line or exact-string replacements and simple renames (faster, no API call)
- native write: creating new files from scratch

FORMAT — use "// ... existing code ..." to represent unchanged sections:
// ... existing code ...
FIRST_EDIT
// ... existing code ...
SECOND_EDIT
// ... existing code ...

CRITICAL RULES:
- ALWAYS wrap changes with markers at start AND end (omitting markers DELETES surrounding code)
- Include 1-2 unique context lines around each edit to anchor the location precisely
- Write a specific 'instructions' param: "I am adding X to function Y" not "update code"
- Preserve exact indentation
- For deletions: show surrounding context, omit the deleted lines
- Batch multiple edits to the same file in one call

DISAMBIGUATION — when a file has repeated patterns, include enough unique context:
  BAD:  just "return result;" (matches many places)
  GOOD: include the unique function signature above it

FALLBACK: If fast_edit fails (API error, timeout), use the native 'edit' tool with exact oldString/newString matching.`;

export function makeMorphEdit(pi: ExtensionAPI) {
  const { z } = pi.zod;
  const parameters = z.object({
    target_filepath: z.string().describe("Path of the file to modify"),
    instructions: z.string().describe(
      "Brief first-person description of what you're changing. Used to disambiguate uncertainty in the edit.",
    ),
    code_edit: z.string().describe(
      'The code changes wrapped with "// ... existing code ..." markers for unchanged sections',
    ),
  });

  return {
    name: "fast_edit",
    label: "Fast Edit",
    description: withToolNote(DESCRIPTION, "fast_edit"),
    parameters,
    approval: "write",
    async execute(
      _toolCallId: string,
      params: Static<typeof parameters>,
      signal: AbortSignal | undefined,
      _onUpdate: AgentToolUpdateCallback | undefined,
      ctx: ExtensionContext,
    ): Promise<AgentToolResult> {
      try {
        const { target_filepath, instructions, code_edit } = params;
        const normalizedCodeEdit = normalizeCodeEditInput(code_edit);
        const filepath = resolve(ctx.cwd, target_filepath);

        const apiKey = MORPH_API_KEY;
        if (!apiKey || !morph) {
          return textToolResult(`Error: MORPH_API_KEY not configured.

To use fast_edit, set the MORPH_API_KEY environment variable.
Get your API key at: https://morphllm.com/dashboard/api-keys

Alternatively, use the native 'edit' tool for this change.`, true);
        }
        const client = morph;

        let originalCode: string;
        try {
          const file = Bun.file(filepath);
          if (!(await file.exists())) {
            if (!normalizedCodeEdit.includes(EXISTING_CODE_MARKER)) {
              throwIfAborted(signal);
              await Bun.write(filepath, normalizedCodeEdit);
              if (signal?.aborted) {
                // The write created a file that did not exist before this call.
                // A cancelled tool must not leave a workspace mutation behind,
                // so roll back the just-created file before rethrowing.
                await unlink(filepath).catch(() => {});
                throwIfAborted(signal);
              }
              return textToolResult(`Created new file: ${target_filepath}\n\nLines: ${normalizedCodeEdit.split("\n").length}`);
            }
            return textToolResult(`Error: File not found: ${target_filepath}

The file doesn't exist and the code_edit contains lazy markers.
For new files, provide the complete content without "${EXISTING_CODE_MARKER}" markers.`, true);
          }
          originalCode = await file.text();
        } catch (error) {
          if (
            error instanceof ToolAbortError ||
            (error instanceof Error && error.name === "AbortError") ||
            signal?.aborted
          ) {
            throw error;
          }
          const message = error instanceof Error ? error.message : String(error);
          return textToolResult(`Error reading file ${target_filepath}: ${message}`, true);
        }

        const hasMarkers = normalizedCodeEdit.includes(EXISTING_CODE_MARKER);
        const originalLineCount = originalCode.split("\n").length;

        if (!hasMarkers && originalLineCount > 10) {
          return textToolResult(`Error: Missing "${EXISTING_CODE_MARKER}" markers.

Your code_edit would replace the entire file (${originalLineCount} lines) because it contains no markers.
This is almost certainly unintended and would cause code loss.

To fix, wrap your changes with markers:
${EXISTING_CODE_MARKER}
YOUR_CHANGES_HERE
${EXISTING_CODE_MARKER}

If you truly want to replace the entire file, use the 'write' tool instead.`, true);
        }

        if (!hasMarkers && originalLineCount > 3) {
          pi.logger.warn(
            `No markers in code_edit for ${target_filepath} (${originalLineCount} lines). Proceeding with full replacement.`,
          );
        }

        throwIfAborted(signal);
        const startTime = Date.now();
        let attemptIndex = 0;
        let result: ApplyEditResult;
        for (;;) {
          throwIfAborted(signal);
          try {
            result = await raceAbort(
              applyMorphFastEdit(
                client,
                {
                  originalCode,
                  codeEdit: normalizedCodeEdit,
                  instruction: instructions,
                  filepath: target_filepath,
                },
                {
                  morphApiKey: apiKey,
                  morphApiUrl: MORPH_API_URL,
                  model: MORPH_FAST_EDIT_MODEL,
                  generateUdiff: true,
                },
                signal,
              ),
              signal,
            );
          } catch (error) {
            const transientMessage = transientMorphFailureMessage(error);
            if (transientMessage === undefined) throw error;
            const delayMs = nextMorphRetryDelay(attemptIndex, startTime, MORPH_TIMEOUT);
            if (delayMs === undefined) throw error;
            pi.logger.warn(
              `Morph fast_edit transient overload for ${target_filepath} on attempt ${attemptIndex + 1}; retrying in ${delayMs}ms: ${transientMessage}`,
            );
            await waitForMorphRetry(delayMs, signal);
            throwIfAborted(signal);
            attemptIndex++;
            continue;
          }
          throwIfAborted(signal);

          const transientMessage = transientMorphFailureMessage(result);
          const delayMs =
            transientMessage === undefined ? undefined : nextMorphRetryDelay(attemptIndex, startTime, MORPH_TIMEOUT);
          if (delayMs !== undefined) {
            pi.logger.warn(
              `Morph fast_edit transient overload for ${target_filepath} on attempt ${attemptIndex + 1}; retrying in ${delayMs}ms: ${transientMessage}`,
            );
            await waitForMorphRetry(delayMs, signal);
            throwIfAborted(signal);
            attemptIndex++;
            continue;
          }
          break;
        }
        const apiDuration = Date.now() - startTime;

        if (!result.success || !result.mergedCode) {
          return textToolResult(`Morph API failed: ${result.error}

Suggestion: Try using the native 'edit' tool instead with exact string replacement.
The edit tool requires matching the exact text in the file.`, true);
        }

        const mergedCode = result.mergedCode;

        if (detectMarkerLeakage(originalCode, mergedCode, hasMarkers)) {
          pi.logger.warn(
            `Marker leakage detected in merged output for ${target_filepath}`,
          );
          return textToolResult(`Morph API produced unsafe output for ${target_filepath}.

Detected placeholder marker text ("${EXISTING_CODE_MARKER}") in merged output.
This means the merge model treated markers as literal code instead of expanding them.

No file changes were written.

Options:
1. Retry with more concrete surrounding context in code_edit
2. Use the native 'edit' tool for exact string replacement
3. Break the change into smaller, more targeted edits`, true);
        }

        const mergedLineCount = mergedCode.split("\n").length;
        const truncation = detectCatastrophicTruncation(
          originalCode,
          mergedCode,
          hasMarkers,
        );

        if (truncation.triggered) {
          pi.logger.warn(
            `Catastrophic truncation detected for ${target_filepath}: ${Math.round(truncation.charLoss * 100)}% char loss, ${Math.round(truncation.lineLoss * 100)}% line loss`,
          );
          return textToolResult(`Morph API produced a potentially destructive merge for ${target_filepath}.

Original: ${originalLineCount} lines (${originalCode.length} chars)
Merged:   ${mergedLineCount} lines (${mergedCode.length} chars)
Loss:     ${Math.round(truncation.charLoss * 100)}% characters, ${Math.round(truncation.lineLoss * 100)}% lines

Because markers were provided, this large shrink is likely unintended.
No file changes were written.

Options:
1. Retry with more precise anchors in code_edit
2. Use the native 'edit' tool for exact string replacement
3. Break the change into smaller edits`, true);
        }

        try {
          await Bun.write(filepath, mergedCode);
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          return textToolResult(`Error writing file ${target_filepath}: ${message}`, true);
        }

        const udiff = result.udiff || "No changes detected";
        const { linesAdded, linesRemoved } = result.changes;
        const originalLines = originalCode.split("\n").length;
        const mergedLines = mergedCode.split("\n").length;

        return textToolResult(`Applied edit to ${target_filepath}

+${linesAdded} -${linesRemoved} lines | ${originalLines} -> ${mergedLines} total | ${apiDuration}ms

\`\`\`diff
${udiff.slice(0, 3000)}${udiff.length > 3000 ? "\n... (truncated)" : ""}
\`\`\``);
      } catch (error) {
        if (
          error instanceof ToolAbortError ||
          (error instanceof Error && error.name === "AbortError") ||
          signal?.aborted
        ) {
          throw error instanceof Error ? error : new ToolAbortError();
        }
        const message = error instanceof Error ? error.message : String(error);
        return textToolResult(message, true);
      }
    },
  } satisfies ToolDefinition<typeof parameters>;
}

type FastApplyConfig = {
  morphApiKey: string;
  morphApiUrl: string;
  model: MorphFastEditModel;
  generateUdiff: boolean;
};

type MorphApplyResponse = {
  id?: string;
  choices?: Array<{ message?: { content?: string | null } }>;
};

async function applyMorphFastEdit(
  client: NonNullable<typeof morph>,
  input: ApplyEditInput,
  config: FastApplyConfig,
  signal?: AbortSignal,
): Promise<ApplyEditResult> {
  if (config.model !== "auto") {
    // Morph SDK 0.2.x applyEdit has no AbortSignal option, so the caller's
    // signal can't cancel this request — only the raceAbort wrapper at the
    // call site stops the caller's wait. Revisit when the SDK exposes signal.
    return client.fastApply.applyEdit(input, {
      morphApiUrl: config.morphApiUrl,
      generateUdiff: config.generateUdiff,
      large: config.model === "morph-v3-large",
    });
  }

  return applyMorphFastEditViaApi(input, config, signal);
}

async function applyMorphFastEditViaApi(
  input: ApplyEditInput,
  config: FastApplyConfig,
  signal?: AbortSignal,
): Promise<ApplyEditResult> {
  const filepath = input.filepath || "file";
  const instruction = input.instruction ?? input.instructions ?? "";

  try {
    const { content: mergedCode, completionId } = await callMorphApplyApi(
      input.originalCode,
      input.codeEdit,
      instruction,
      filepath,
      config,
      signal,
    );
    return {
      success: true,
      mergedCode,
      udiff: config.generateUdiff
        ? generateUdiff(input.originalCode, mergedCode, filepath)
        : undefined,
      changes: countChanges(input.originalCode, mergedCode),
      completionId,
    };
  } catch (error) {
    return {
      success: false,
      changes: { linesAdded: 0, linesRemoved: 0, linesModified: 0 },
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

async function callMorphApplyApi(
  originalCode: string,
  codeEdit: string,
  instruction: string,
  filepath: string,
  config: FastApplyConfig,
  signal?: AbortSignal,
): Promise<{ content: string; completionId?: string }> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), MORPH_TIMEOUT);
  // Link the caller's cancellation so aborting the tool stops the in-flight
  // HTTP request, not just the JS-level wait (raceAbort) wrapping it.
  const onAbort = () => controller.abort();
  if (signal?.aborted) controller.abort();
  else signal?.addEventListener("abort", onAbort);
  const message = `<instruction>${instruction}</instruction>
<code>${originalCode}</code>
<update>${codeEdit}</update>`;

  try {
    const response = await fetch(`${config.morphApiUrl}/v1/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.morphApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: config.model,
        messages: [{ role: "user", content: message }],
      }),
      signal: controller.signal,
    });

    const responseText = await response.text();
    if (!response.ok) {
      throw new Error(`Morph API ${response.status} ${response.statusText}: ${responseText}`);
    }

    let data: MorphApplyResponse;
    try {
      data = JSON.parse(responseText) as MorphApplyResponse;
    } catch {
      throw new Error("Morph API returned invalid JSON");
    }

    const content = data.choices?.[0]?.message?.content;
    if (!content) throw new Error("Morph API returned empty response");
    return { content, completionId: data.id };
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      // Caller cancelled -> propagate the abort; otherwise it was our timeout.
      if (signal?.aborted) throw error;
      throw new Error(`Morph API request timed out after ${MORPH_TIMEOUT}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
    signal?.removeEventListener("abort", onAbort);
  }
}
