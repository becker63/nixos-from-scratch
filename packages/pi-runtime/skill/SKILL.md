---
name: jev-control
description: Batch bounded semantic coding judgments in Fabric; explicit conservative TypeScript branches preserve uncertainty.
---
Use at meaningful transitions: candidate localization, before editing, before a worker,
after verification failures, after repeated investigation, and before completion.
Run one vector over the same minimized evidence; follow it with several deterministic
actions. Arithmetic, file facts, test outcomes and compiler diagnostics come from
code/tools. Jev never generates code, commands, prose or arbitrary next actions.

Read `policy.ts` beside this skill for a checked Fabric program template. Replace its
synthetic observation with a compact object assembled by deterministic tools: finite
candidate file/symbol/span IDs and excerpts, current task, patch summary, exact check
outcomes, bounded worker report IDs, investigation history. Do not include secrets,
raw auth, environment dumps or unrestricted tool logs. Keep the finite question
criteria; add independent Noul/Choice/Score heads to the same evaluation where useful.
Use localization distributions to rank candidates and distinguish implementation
from incidental callers. Batch one relevance head per bounded candidate if necessary.
Use evidence sufficiency/architecture ambiguity to decide whether to inspect more or
spend another Codex turn. Gate workers on independence AND information gain; rank
bounded reports with Choice before adding selected excerpts to Main's context.

The template returns an explicit decision union and the entire answer distributions.
Thresholds are conservative starting values, not scientifically calibrated. A failed
provider returns `unknown/provider_failure`; stop semantic-dependent actions and report
it. Do not silently invoke Codex instead. Retry at most once after explicit backoff
for a transient provider failure, with fresh evidence and a remaining budget.

Worker policy: Fabric `agents.run`/`spawn`, Pi runner, model
`openai-codex/gpt-6.1-sol`, medium thinking, explicit cwd/task/tool allowlist,
JSON `schema`, timeout <=300000ms, maxConcurrent 4, maxPerExecution 4, maxDepth 1.
Require both worker heads >=0.90. Usually launch one. Use readOnly:true for research;
only allow repository writes when needed. Inspect structured results and failures.
Verify exact outcomes after any semantic choice; confidence never proves completion.
Initialize LSP before editing; reread after first server startup to send didOpen.
An initial empty diagnostics cache is not proof of a clean compile.

For prolonged work, optionally use Fabric's `jev.spawn` observer/foreman on
`agent_settled` or `tool_error`, maxAdvice 2, maxEvaluations 8, maxChars 4096,
queueSize 4. Select only sanitized state; do not include raw toolResults. Batch drift,
redundancy, failure class, sufficiency and completion heads per event. No observer
on every tool call. Advice text comes from fixed TypeScript branches.

Inspect `/fabric status`, `/fabric dashboard` (Activity view), `/fabric agents`
and `/status`; query `jev.status({})` inside Fabric for provider/run status. Assessment traces record durations, operations, Jev/classifier calls,
reported usage/cost and failures without code, arguments, results or error prose.
Count test invocations from tool activity and use test commands with clear labels.
