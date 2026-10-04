import type { CompactResult } from "@morphllm/morphsdk";
import type {
  AgentToolResult,
  ExtensionAPI,
  ExtensionContext,
  SessionBeforeCompactEvent,
  SessionBeforeCompactResult,
} from "@oh-my-pi/pi-coding-agent/extensibility/extensions/types";
import { throwIfAborted } from "@oh-my-pi/pi-coding-agent/tools/tool-errors";
import { COMPACT_RATIO, MORPH_HANDLER_BUDGET_MS } from "./config.js";
import { compactClient, morphReady } from "./morph-clients.js";
import { raceAbort } from "./abort.js";
import { nextMorphRetryDelay, transientMorphFailureMessage, waitForMorphRetry } from "./retry.js";

export function formatCompressionPercent(result: CompactResult): number {
  return Math.round(result.usage.compression_ratio * 100);
}

export function compactResultText(result: CompactResult): string {
  const output = result.output?.trim();
  if (output) return output;

  return (result.messages || [])
    .map((message) => `[${message.role}] ${message.content}`)
    .join("\n\n")
    .trim();
}

type MorphCompactMessage = { role: string; content: string };
type MessageWithRole = { role?: string; content?: unknown; toolName?: string };
type ContentPart = {
  type?: string;
  text?: string;
  thinking?: string;
  name?: string;
  arguments?: Record<string, unknown>;
};

type BoundedBuffer = { out: string; limit: number };

function bufferFull(buf: BoundedBuffer): boolean {
  return buf.out.length >= buf.limit;
}

function appendBounded(buf: BoundedBuffer, text: string): void {
  if (buf.out.length >= buf.limit) return;
  const remaining = buf.limit - buf.out.length;
  buf.out += text.length > remaining ? text.slice(0, remaining) : text;
}

// Serialize a JSON value into `buf`, stopping once the output budget is spent.
// Result is byte-identical to JSON.stringify(value).slice(0, limit) for inputs
// that fit, but large values are never fully stringified: strings are sliced
// before escaping (escaped length >= raw length, so `remaining` raw chars always
// cover the remaining budget) and the walk halts as soon as the budget is full.
function appendBoundedJson(buf: BoundedBuffer, value: unknown): void {
  if (bufferFull(buf)) return;

  if (value === null || typeof value !== "object") {
    if (typeof value === "string") {
      const remaining = buf.limit - buf.out.length;
      const slice = value.length > remaining ? value.slice(0, remaining) : value;
      appendBounded(buf, JSON.stringify(slice));
      return;
    }
    if (value === undefined || typeof value === "function" || typeof value === "symbol") {
      appendBounded(buf, "null");
      return;
    }
    appendBounded(buf, JSON.stringify(value as number | boolean));
    return;
  }

  if (Array.isArray(value)) {
    appendBounded(buf, "[");
    for (let i = 0; i < value.length; i++) {
      if (bufferFull(buf)) break;
      if (i > 0) appendBounded(buf, ",");
      const el = value[i];
      if (el === undefined || typeof el === "function" || typeof el === "symbol") {
        appendBounded(buf, "null");
      } else {
        appendBoundedJson(buf, el);
      }
    }
    appendBounded(buf, "]");
    return;
  }

  appendBounded(buf, "{");
  let first = true;
  for (const [key, v] of Object.entries(value as Record<string, unknown>)) {
    if (bufferFull(buf)) break;
    if (v === undefined || typeof v === "function" || typeof v === "symbol") continue;
    if (!first) appendBounded(buf, ",");
    first = false;
    appendBounded(buf, JSON.stringify(key));
    appendBounded(buf, ":");
    appendBoundedJson(buf, v);
  }
  appendBounded(buf, "}");
}

function boundedJsonStringify(value: unknown, limit: number): string {
  const buf: BoundedBuffer = { out: "", limit };
  appendBoundedJson(buf, value);
  return buf.out;
}

function serializeContentPart(part: ContentPart): string {
  switch (part.type) {
    case "text":
      return part.text || "";
    case "toolCall": {
      const inputStr = boundedJsonStringify(part.arguments || {}, 500);
      return `[Tool: ${part.name || "unknown"}] ${inputStr}`;
    }
    case "thinking":
    case "redactedThinking":
    case "image":
      return "";
    default:
      return "";
  }
}

function serializeMessageContent(message: MessageWithRole): string {
  if (typeof message.content === "string") return message.content;
  if (!Array.isArray(message.content)) return "";

  // Tool results are capped at 2000 chars. Append non-empty serialized parts
  // straight into a bounded buffer and stop once it is full, so a large
  // multi-part tool result is never fully materialized before the cap applies.
  if (message.role === "toolResult" && message.toolName) {
    const buf: BoundedBuffer = { out: "", limit: 2000 };
    let appended = false;
    for (const part of message.content) {
      if (bufferFull(buf)) break;
      const text = serializeContentPart(part as ContentPart);
      if (text.length === 0) continue;
      if (appended) appendBounded(buf, "\n");
      appendBounded(buf, text);
      appended = true;
    }
    if (!appended) return "";
    return `[Tool: ${message.toolName}]\nOutput: ${buf.out}`;
  }

  const parts = message.content
    .map((part) => serializeContentPart(part as ContentPart))
    .filter((text) => text.length > 0);
  return parts.join("\n");
}

export function serializeAgentMessagesForMorph(
  messages: MessageWithRole[],
): MorphCompactMessage[] {
  return messages
    .map((message) => {
      const msg = message as MessageWithRole;
      return {
        role: msg.role || "user",
        content: serializeMessageContent(msg),
      };
    })
    .filter((message) => message.content.length > 0);
}

export function textToolResult(text: string, isError = false): AgentToolResult {
  return { content: [{ type: "text", text }], isError: isError || undefined };
}

export function makeBeforeCompact(pi: ExtensionAPI, handlerBudgetMs = MORPH_HANDLER_BUDGET_MS) {
  return async function beforeCompact(
    event: SessionBeforeCompactEvent,
    ctx: ExtensionContext,
  ): Promise<SessionBeforeCompactResult | undefined> {
    if (!morphReady() || !compactClient) return undefined;

    const prep = event.preparation;

    // Morph substitutes exactly two of omp's compaction methods: `soft` and
    // `handoff`. omp's resolveMethodSettings encodes the selected method as a
    // (strategy, remoteEnabled) pair: `remote` is the only method with
    // remoteEnabled true, and snapcompact/shake each carry their own strategy.
    // So "remote disabled" plus a context-full-or-handoff strategy names
    // {soft, handoff} exactly. Everything else stays with the host, including
    // an SDK consumer that never went through resolveMethodSettings.
    const { strategy, remoteEnabled } = prep.settings;
    if (remoteEnabled !== false) return undefined;
    if (strategy !== "context-full" && strategy !== "handoff") return undefined;

    // `/compact <focus>` focus text becomes the Morph compaction query. It never
    // widens the gate above: a focused compaction the host routed to remote or
    // snapcompact still belongs to the host.
    const focus = event.customInstructions?.trim() || undefined;

    // The host applies a hook-provided summary verbatim and keeps only entries
    // from firstKeptEntryId onward, so anything the native summarizer would fold
    // in must be folded here too: the previous compaction's summary (iterative
    // update) and, on a split turn, the turn-prefix messages.
    const summarizable: MessageWithRole[] = [];
    if (prep.previousSummary) {
      summarizable.push({ role: "user", content: `[Summary of earlier history]\n${prep.previousSummary}` });
    }
    summarizable.push(...(prep.messagesToSummarize as MessageWithRole[]));
    if (prep.isSplitTurn && prep.turnPrefixMessages.length > 0) {
      summarizable.push(...(prep.turnPrefixMessages as MessageWithRole[]));
    }
    if (summarizable.length === 0) return undefined;

    const input = serializeAgentMessagesForMorph(summarizable);
    if (input.length === 0) return undefined;

    throwIfAborted(event.signal);
    // OMP caps session_before_compact handlers at 30s
    // (EXTENSION_HANDLER_TIMEOUT_MS). Self-abort just under it so a slow Morph
    // call falls back to native here, instead of OMP reporting "handler timed
    // out" and orphaning the in-flight request.
    const compactSignal = event.signal
      ? AbortSignal.any([event.signal, AbortSignal.timeout(handlerBudgetMs)])
      : AbortSignal.timeout(handlerBudgetMs);
    const startTime = Date.now();
    try {
      let attemptIndex = 0;
      let result: CompactResult;
      for (;;) {
        throwIfAborted(event.signal);
        try {
          result = await raceAbort(
            compactClient.compact({
              messages: input,
              compressionRatio: COMPACT_RATIO,
              preserveRecent: 0,
              query: focus,
            }),
            compactSignal,
          );
        } catch (error) {
          const transientMessage = transientMorphFailureMessage(error);
          if (transientMessage === undefined) throw error;
          const delayMs = nextMorphRetryDelay(attemptIndex, startTime, handlerBudgetMs);
          if (delayMs === undefined) throw error;
          pi.logger.warn(
            `Morph compaction transient overload on attempt ${attemptIndex + 1}; retrying in ${delayMs}ms: ${transientMessage}`,
          );
          await waitForMorphRetry(delayMs, compactSignal);
          attemptIndex++;
          continue;
        }
        break;
      }
      throwIfAborted(event.signal);

      const summary = compactResultText(result);
      if (!summary) return undefined;

      if (ctx.hasUI) {
        ctx.ui.notify(`Morph compacted (${formatCompressionPercent(result)}% kept)`, "info");
      }

      const compaction = {
        summary,
        firstKeptEntryId: prep.firstKeptEntryId,
        tokensBefore: prep.tokensBefore,
      };
      return { compaction };
    } catch (error) {
      if (event.signal?.aborted) throw error;
      const message = error instanceof Error ? error.message : String(error);
      pi.logger.warn("Morph compaction failed; falling back to native compaction", { error: message });
      return undefined;
    }
  };
}
