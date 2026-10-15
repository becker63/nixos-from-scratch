# Pi semantic-policy experiment

Pi 1.0.4 / Fabric 0.108.1 remain pinned in `package-lock.json`. Existing strict
TypeScript/QuickJS, LSP capture, direct TypeSafe credential launcher, Fabric Pi
workers and Alacritty SemanticTrace are retained. No second agent framework.

## User interface

In Pi:

```
/mode             # show current mode
/mode jev         # pure finite-action policy; subsequent ordinary task messages
/mode hybrid      # explicit return to the generative Pi/Fabric agent
```

Alternatively: `pi --agent-mode jev --jev-grammar J2 -p 'Fix the bug and verify the change.'`
Grammar levels: `--jev-grammar J0|J1|J2|J3`. Comparison policy:
`--jev-policy jev|random|heuristic`. Switching requires an idle task. `/jev-stop` cancels an active finite task. Pure mode
withdraws model-callable tools and consumes input before Pi's generative loop.
Initialization/action/provider failures also consume input, never fall through.
Only an explicit `/mode hybrid` reenables generation. CLI pure mode starts with
its guard already selected; slash-command mode sets the same guard.

The patched host `ModelRuntime.stream`, `streamSimple`, and `streamDeferred`
reject generative requests before provider dispatch while pure mode is active.
Fabric's host registry also rejects `agents.*`. These guards are independent of
instructions and provider-request event exceptions (which upstream Pi swallows).
Use a NEW process with the newly built runtime: old imported modules cannot acquire
the provider guard merely by reloading an extension.

## Pure kernel

```
task -> bounded StateFrame -> phase-specific indexed legal actions
     -> one Jev policy batch -> deterministic macro -> exact observation -> repeat
```

Files: `jev-agent/{state,tasks,actions,transforms,policy,controller}.ts`.

TaskKind classification precedes reproduction: Locate/Inspect return existing
paths, symbols, or exact relationship facts without tests or mutations; Verify
runs existing checks without edits; only Repair enters the repair phases below.
Unsupported requests terminate explicitly. `/jev-receipt` shows full diagnostics;
`--jev-receipt` enables full print-mode receipts. Normal results are concise.

Actual Alacritty navigation and current-source policy repair, with unchanged
heuristic and three seeded random comparisons: [task-shape report](../../docs/jev-task-shapes.md)
and `jev-current-source-results.json`. Reproducer: `jev-agent/self-repair.mjs`.
Random seed offset: `--jev-seed N`.
The host imports Fabric's public `JevClient`, `JevCredentials`, route and config
normalizers: the SAME typed TypeSafe implementation as `jev.evaluate`, not an
independent transport. Credential resolution stays host-side (Pi auth, route env,
then the existing private command). No keys or auth files enter state frames.

Design influences (decomposition principles, not copied implementations):
SWE-agent's constrained ACI/bounded views/checked edits; Agentless's repository →
file → symbol → span narrowing; AutoCodeRover's reproduce/localize/repair/verify;
browser agents' indexed targets and candidate selection; CodeAct/Voyager's
macro-actions; TBar/Getafix's finite templates and compatible donors.

### Phases and IDs

| Phase | Legal actions |
| --- | --- |
| Localize | InspectFamily, InspectFile |
| Inspect | InspectSymbol (definition, bounded nearby tests, imports in source) |
| Transform | ApplyEdit from generated, type-filtered candidates |
| Verify | VerifyAffectedRegion over enumerated Node test targets |
| Recover | Revert exact previous snapshot, then alternate candidate |
| Stop | exact current checks + supported StopSuccess; otherwise NeedsGeneration |

Files `F…`, repository regions `G…`, symbols `S…`, nodes `N…`, edits `E…`, checks
`T…`, actions `A…` are task-local IDs. Paths/identifiers/replacements are resolved
only from host tables. Region → file → symbol → node narrowing bounds localization.
More than eight edits get one batched relevance pass then Choice over the top eight.
Small action sets get one eight-head policy vector. Distributions are retained.

J0: inspect/test only. J1: single-file exact compiler fix-its, without commands or
new files. J2 adds numeric operator replacement, same-type in-scope variable
replacement, and required argument insertion from compatible in-scope values.
J3 adds existing signature-compatible callable replacement. Revert is available at
all repair levels. J4/J5 are NOT implemented. Literal/guard/novel-code generation is
NOT implemented. This is deliberately a small grammar, not a general repair system.

Compiler ASTs locate spans. TypeChecker eliminates incompatible scope/type donors;
every instantiated patch must have zero source-file syntax/type diagnostics before
it becomes legal. Original text spans must still match at application. One
unverified edit at a time; unsuccessful terminal outcomes restore its exact prior
snapshot unless an external mutation makes restoration unsafe. No invented names,
replacement text, paths, or shell strings come from Jev.

A pending mutation cannot produce Success without its enumerated exact check,
even if Jev's action choice is flat. Budget/cancellation termination can instead
restore an unverified edit without running another check.
Success requires current-revision passing checks and semantic finish support:
strong goal support, or a >=.90 finish-choice probability with <=.05 unknown and
positive (>=.50) goal support. Other action choices require top >=.55 and margin
>=.10. These are **provisional reconciliation rules, not calibrated probabilities**.
The live pilot exposed why a flat mandatory-verification choice must not veto an
exact lifecycle obligation; it also exposed inconsistent independent completion
heads. Full distributions preserve these observations instead of hiding them.

### Scope and budgets

Navigation enumerates up to 2048 bounded config/source/document objects at depth
seven (48KB each), compresses to 24 candidates using path and source-token facts,
and asks Jev to choose IDs, never paths or prose. Repair grammar: JS/TS files (64), Node
`*.test.*`/`*.spec.*` targets (8), bounded depth and excerpts; no symlinks, hidden,
credential, `.env`, vendor/build/node_modules files in candidate enumeration.
Type filtering is source-file-local, not a whole-repository proof. Imports may be
read by TypeScript but are not automatically transmitted as evidence.
No LSP call graph, Grit repair engine, arbitrary search generation, package command
invention, or generic language support is claimed. Empty discovery yields
NotFound for navigation or explicit Unsupported/NeedsGeneration as appropriate;
it does not invent a search string. Exhausted regions are retired before other
regions are searched. Check dependencies come from pinned runtime modules via
credential-free NODE_PATH and exact TypeScript module-resolution fallback, not
ambient npm installs or a checkout node_modules assumption.

Defaults: 24 actions/iterations, 32 Jev evaluations, 120 seconds, six transformations,
ten exact checks, two repeated-state observations. Provider failure, cancellation,
budget exhaustion, and NeedsGeneration are structured distinct terminals. State
memory is finite repository/evidence/revision tables, not prose/transcript memory.
An unsupported operation is a generation boundary, NOT a request to Codex.

Enumerated checks use Node argv with `execFile`, never a shell. Test subprocesses
receive a small environment without API-key variables. **This is not an OS sandbox**:
trusted repository tests can execute arbitrary code, read HOME, fork or use network.
Malicious tests could call unrelated external services outside Pi's guard. This
experiment's zero-generation guarantee covers the host kernel, Pi provider dispatch
and Fabric worker dispatch, not all possible code inside an adversarial repository.

## Incremental hybrid controller

```
exact world -> dependency revisions -> dirty registers -> one Jev vector
            -> full semantic state -> typed policy -> context / permits / escalation
```

`semantic-state.ts` owns revisions and twelve register cells; `semantic-policy.ts`
owns distribution shape and provisional thresholds; `semantic-controller.ts` owns
barriers, evidence admission, opaque single-use revision-bound permits and exact
facts. `semantic-extension.ts` is the ONE mode/controller extension, not overlapping
observer extensions. Fabric registry invocation is patched fail-loud; an async-local
host scope prevents duplicate native middleware and admission deadlocks.

Dependencies are deterministic world revisions, not predictions from another head
in the same vector (independent Jev heads cannot consume freshly predicted peers).
Each cell stores its full Noul/Choice/Score answer, epoch and dependency stamp.

| Register | Type | Exact dependencies / invalidators | Consumers |
| --- | --- | --- | --- |
| locality | Choice | task, candidate changes, evidence changes | evidence/reasoning |
| evidenceSufficiency | Noul | task, candidates, source evidence, relations, workers | mutation/worker/evidence/reasoning |
| architectureNeed | Score | task, evidence, relations | worker/reasoning |
| ambiguity | Score | task, candidates, evidence, workers | evidence/reasoning |
| mutationRisk | Score | task, proposed edit, evidence, relations | mutation |
| workerInformationGain | Noul | task, evidence, workers, repeated investigation | worker/reasoning |
| goalDrift | Noul | task, history, mutation, workers | reasoning/settlement |
| investigationRedundancy | Noul | task, history, evidence | evidence/reasoning |
| failureClass | Choice | exact verification/failure fingerprint, mutation | failure/settlement |
| verificationDebt | Noul | task, mutation, verification | failure/settlement |
| completionSupport | Noul | task, mutation, verification, workers, evidence | settlement |
| anotherGenerativeTurnValue | Noul | task, evidence, verification, workers, history | reasoning/settlement |

Identical observations are cache hits; a changed verification invalidates debt and
completion without invalidating locality. Edits invalidate evidence and mutation
revisions. Input/correction starts an epoch. Relation revisions are reserved for
future relationship acquisition (not fabricated call-graph evidence).

The membrane replaces outer Fabric results with bounded host-selected evidence and
semantic/exact summaries. Candidates and worker reports share batched admission
heads; byte counts and rough bytes/4 token estimates are distinct from provider
usage. Exact shell failures are bounded; raw model-returned dumps are not admission
authority. This sacrifices arbitrary guest return values intentionally and is an
experimental compatibility limitation.

Mutation and worker permits require fresh semantic cells and exact facts. Settlement
uses `agent_before_settle`, not notification-only `agent_settled`; unsupported
completion gets fixed host text, with at most two continuations. Jev never writes
steering prose. Host hooks own semantics even if Codex never calls `jev.evaluate`.
Read/search still work on provider failure; mutation, workers and readiness fail
closed. No generative substitute. Hybrid policies can be compared using the trusted
startup `PI_SEMANTIC_POLICY=jev|constant|heuristic|off`.

Hybrid shell policy is a conservative small command grammar; obvious `sed -i`,
redirection, command chaining, interpreter snippets and interactive sessions cannot
skip permits. Named test commands can still execute arbitrary repository code;
unknown captured extensions or externally loaded providers are not an OS security
boundary. Hybrid generative Main still exists: reasoning barriers record semantic
escalation value but do NOT veto every subsequent model turn. The information-gain
finite-action selector is separately instrumented experimental API, not a general
autonomous evidence scheduler.

## Trace and telemetry

Existing Alacritty protocol/rendering is unchanged. Candidate generation uses Search;
policy lifetimes use Jev with head counts; actual mutations use Edit; checks use
Verify; generation boundaries use failed Tool pulses; success uses passed pulses.
The pure input handler never starts the Codex agent loop, so these dense policy/
deterministic trajectories have no Codex generation scope. No arbitrary text labels
or prompts go over terminal IPC.

Metrics include steps, heads/evaluations/tokens/latency, deterministic time, candidate
counts through filters/ranking, phase changes, action families, mutations/reverts,
checks/failures, repeats, zero host generative calls and wall time. Hybrid also tracks
invalidations, freshness hits, permits/denials, context bytes and continuations.
Fabric's native JevResponse exposes token usage but **does not expose billed cost**;
pure receipts use `null`, never an invented estimate. Distributions live in structured
host receipts; terminal IPC carries only enums/counts/lifecycle facts.

## Verification

Build ONLY the relevant runtime (never a system closure):

```
nix build .#pi-runtime --no-link
npm run test:semantic                 # inside packaged runtime/dependency tree
npm run test:jev-mode:live            # explicit real TypeSafe opt-in
```

The fixture test compiles strict TypeScript, tests `/mode jev` and `/mode hybrid`,
ordinary input handling, fail-closed outage, all three provider guards, J0's limit,
A–D's finite repair families, E's missing logic and explicit budgets. The live path
runs actual CLI tasks, with identical fixtures for Jev/random/heuristic policies.
`jev-fixture-results.json` is a content-free/probability receipt, not source/log/auth
storage. Seeded random is one trajectory; the heuristic intentionally recognizes
simple repair descriptions. Neither is a representative performance benchmark.
See `docs/jev-agent-experiment.md` for the pilot's measured results and limitations.

`pi-validate` runs the three strict deterministic semantic/trace/kernel checks.
`pi-validate --live` additionally runs the explicit real-provider CLI ladder.
LSP capture configuration is preserved, but these checks do not claim a fresh LSP
server smoke test; the old unrestricted-shell validation expectations are retired.
