import { ToolAbortError } from "@oh-my-pi/pi-coding-agent/tools/tool-errors";

// Map an aborted signal to the same error `throwIfAborted` would raise: the
// signal's own reason when it is already a ToolAbortError, otherwise a fresh one.
function abortReason(signal: AbortSignal): Error {
  const reason = signal.reason instanceof Error ? signal.reason : undefined;
  return reason instanceof ToolAbortError ? reason : new ToolAbortError();
}

// Reject as soon as `signal` aborts instead of blocking until the in-flight
// promise settles. The original promise keeps running in the background; its
// settlement is still awaited here so a late rejection can never surface as an
// unhandled rejection once an abort has already won the race.
export function raceAbort<T>(promise: Promise<T>, signal: AbortSignal | undefined): Promise<T> {
  if (!signal) return promise;
  if (signal.aborted) {
    promise.catch(() => {});
    return Promise.reject(abortReason(signal));
  }
  const { promise: out, resolve, reject } = Promise.withResolvers<T>();
  const onAbort = () => reject(abortReason(signal));
  signal.addEventListener("abort", onAbort, { once: true });
  void (async () => {
    try {
      resolve(await promise);
    } catch (err) {
      reject(err);
    } finally {
      signal.removeEventListener("abort", onAbort);
    }
  })();
  return out;
}
