import { raceAbort } from "./abort.js";

export type TransientFailureMessage = string | undefined;

const MORPH_TRANSIENT_RETRY_DELAYS_MS = [250, 500, 1_000] as const;
const MORPH_TRANSIENT_ERROR_RE = /\b429\b|\b50[234]\b|service overloaded|please retry shortly|rate limited/i;

// Returns the transient-overload message text if `value` represents a transient
// Morph overload failure — either a thrown Error whose message matches
// MORPH_TRANSIENT_ERROR_RE, or an object with `success === false` and a string
// `error` matching the same pattern. Returns undefined for successful results,
// non-object/non-Error values, missing error text, or non-transient failures
// (so callers never retry on unrelated failures).
export function transientMorphFailureMessage(value: unknown): TransientFailureMessage {
  if (value instanceof Error) {
    return MORPH_TRANSIENT_ERROR_RE.test(value.message) ? value.message : undefined;
  }
  if (value && typeof value === "object" && "success" in value && value.success === false && "error" in value) {
    const error = value.error;
    if (typeof error === "string" && MORPH_TRANSIENT_ERROR_RE.test(error)) {
      return error;
    }
  }
  return undefined;
}

// Returns the delay (ms) to wait before the next retry attempt, indexed by the
// zero-based FAILED attempt (0 = first failure, so the first retry uses
// MORPH_TRANSIENT_RETRY_DELAYS_MS[0]). Returns undefined once the retry budget
// (array length) is exhausted, or once scheduling the delay would push past
// `timeoutMs` measured from `startedAt`.
export function nextMorphRetryDelay(
  attemptIndex: number,
  startedAt: number,
  timeoutMs: number,
): number | undefined {
  const delayMs = MORPH_TRANSIENT_RETRY_DELAYS_MS[attemptIndex];
  if (delayMs === undefined) return undefined;
  if (Date.now() - startedAt + delayMs > timeoutMs) return undefined;
  return delayMs;
}

// Sleeps for delayMs, rejecting immediately if `signal` aborts during the wait
// (via raceAbort), and always clearing the underlying timer.
export async function waitForMorphRetry(delayMs: number, signal: AbortSignal | undefined): Promise<void> {
  let clearTimer: (() => void) | undefined;
  const sleep = new Promise<void>((resolve) => {
    const timer = setTimeout(resolve, delayMs);
    clearTimer = () => clearTimeout(timer);
  });
  try {
    await raceAbort(sleep, signal);
  } finally {
    clearTimer?.();
  }
}
