// Fail-loud patch against pinned pi-fabric. Only enum/number facts leave the host hook.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
const root = process.argv[2];
function replace(path, anchor, replacement) {
  let text = readFileSync(path, 'utf8');
  if (text.split(anchor).length !== 2) throw new Error(`Semantic hook anchor drift: ${path}`);
  writeFileSync(path, text.replace(anchor, replacement));
}
replace(join(root, 'chunks/chunk-5QMCSJ42.js'),
  '        args: argsPreview\n      });',
  `        args: argsPreview,
        semanticCount: ref === "jev.evaluate" && catalog.args?.questions && typeof catalog.args.questions === "object"
          ? Math.min(65535, Object.keys(catalog.args.questions).length) : 0
      });`);
replace(join(root, 'fabric-runtime-state.js'),
  '    const observeInvocation = (event) => {',
  `    const semanticCalls = new Map();
    const semanticKind = (ref) => ({
      "jev.evaluate": "jev", "agents.run": "worker", "agents.spawn": "worker",
      "pi.read": "read", "pi.find": "search", "pi.grep": "search", "pi.ls": "search",
      "pi.edit": "edit", "pi.write": "edit", "pi.bash": "shell-command",
      "native.pi.read": "read", "native.pi.find": "search", "native.pi.grep": "search",
      "native.pi.edit": "edit", "native.pi.write": "edit", "native.pi.bash": "shell-command"
    })[ref] ?? "tool";
    const observeInvocation = (event) => {
      // Correlation ids are host-owned; never emit arguments/results/errors/prompts.
      let safe;
      if (event.type === "call_start" && semanticCalls.size < 256) {
        safe = { kind: semanticKind(event.ref), count: event.semanticCount ?? 0 };
        semanticCalls.set(event.callId, safe);
        safe = { ...safe, phase: "start", status: "active" };
      } else if (event.type === "call_end") {
        const previous = semanticCalls.get(event.callId);
        semanticCalls.delete(event.callId);
        if (previous) safe = { ...previous, phase: "finish", status: event.success ? "passed" : "failed" };
      }
      if (safe) {
        try { this.#emitEvent?.("pi-fabric:semantic-v1", {
          version: 1, parent: options.parentToolCallId, key: event.callId, ...safe
        }); } catch { /* observation must never change execution */ }
      }`);
