# Finite Jev coding kernel: pilot report

## Mechanism

```
user task -> bounded exact StateFrame -> phase-specific legal action IDs
          -> batched native Fabric Jev -> deterministic macro -> exact observation
```

The ONE controller extension registers `/mode jev`, `/mode hybrid`, `/mode`, and
`/jev-stop`. CLI equivalent: `--agent-mode jev`. Pure input is consumed before the
Pi generative loop, including failures. Patched ModelRuntime streaming entry points
reject generation independently of prompts, and Fabric's host registry rejects
workers. Returning NeedsGeneration never launches Codex or a Pi worker.

Implementation: `packages/pi-runtime/jev-agent/`, integrated through
`packages/pi-runtime/semantic-extension.ts`; phase/action/terminal unions are strict
TypeScript. The existing incremental controller and trace remain in place.

## Grammar and enumeration

Localize → Inspect → Transform → Verify → Recover → Stop. Region/file/symbol/node/
edit/check/action IDs resolve through task-local host tables. The model cannot supply
paths, source replacements, commands or symbols. Viewer macro-actions gather bounded
source and adjacent tests. One mutation at a time, exact original-span check, exact
compiler/type filtering, and exact snapshot reversion on unsuccessful termination.
Unvisited files are inspected before a local empty transform set is treated as a
missing capability. Eight-action Choice bound; larger edit sets have one batched
relevance narrowing pass. No fixture below exercised that large-action ranking path.

J0: observation/checks. J1: restricted single-file compiler fix-its. J2: numeric
operator changes, same-type in-scope variable replacements, and required argument
insertion from existing compatible values. J3: signature-compatible existing helper
replacement. No novel algorithm, literal synthesis, guard synthesis or new function
generation. No claim of an LSP/whole-project type proof; filters are source-file-local.

## Development observations

The first real-policy run was rejected by native Fabric JSON validation because
absent optional frame fields were still `undefined`. Frames are now explicitly
projected into finite JSON before inference; no silent model fallback occurred.

After that, real Jev selected repairs for A–D, but Choice on mandatory verification
was flat (e.g. Verify .45, NeedsGeneration .35, unknown .20). TypeScript now requires
the generated exact check after any mutation regardless of that distribution.

Next, passing repairs produced concentrated finish choices (.98–.99) but lower
independent goal-support heads (.71–.77). The provisional policy consumes both:
current exact verification plus strong goal support OR concentrated finish choice
and positive goal support. These thresholds are not statistically calibrated.
Responses remain full distributions, not collapsed boolean claims.

An early random baseline selected the distractor and stopped without inspecting the
remaining implementation. Localization recovery was corrected to inspect remaining
finite targets; the bounded random arm was then rerun. This matters more than merely
calling a classifier many times.

## Frozen packaged acceptance (mechanism check, not a benchmark)

Task text for EVERY actual CLI run: **“Fix the bug and verify the change.”** It does
not name Jev, IDs or repair families. These small repositories contain a buggy typed
source, an exact Node test and a plausible distractor. Tasks are generated once by
the fixture harness, not by a generative model during agent execution.

| Fixture | Grammar | Legal actions¹ | Jev calls / heads | Steps² | Jev result | Wall ms | Random | Heuristic |
| --- | --- | ---: | ---: | ---: | --- | ---: | --- | --- |
| A: <= instead of < | J2 | 8 | 5 / 40 | 4 | Success | 4984 | Success (12 steps) | Success (4) |
| B: start instead of end | J2 | 6 | 5 / 40 | 4 | Success | 3655 | Success (6) | Success (4) |
| C: subtract instead of existing add | J3 | 11 | 5 / 40 | 4 | Success | 3222 | Exhausted (21) | Success (4) |
| D: missing existing end argument | J2 | 8 | 5 / 40 | 4 | Success | 2894 | Success (9) | Success (4) |
| E: checksum algorithm absent | J3 | 5 | 4 / 32 | 3 | NeedsGeneration | 1474 | NeedsGeneration (4) | NeedsGeneration (4) |

¹ Cumulative legal nonterminal actions across observations, not unique edits.
² Completed transition iterations before terminal selection; terminal selection is
not included in this counter. All fifteen arms in this table were rerun against the SAME frozen built package:
`/nix/store/gpkjxbg8mykpjaq68lqy6fq0bd34rg5h-pi-runtime-1.0.4`.
The content-free receipt is `packages/pi-runtime/jev-fixture-results.json`.
E inspected the remaining distractor before declaring the grammar boundary.

A–D's final passing runs each made one mutation and ran the exact checks twice
(reproduce, then verify). E made zero mutations and ran its failing check once.
Random used a fixed deterministic seed trajectory, not many independent trials.
The simple heuristic recognizes common repair descriptions and is deliberately a
strong, fixture-informed dumb comparison. It matched Jev on A–D and was faster.

Measured Jev totals for these five receipts: 24 evaluations, 192 heads, **26,119 input
and 4,912 output tokens**, 5,245 ms inference latency, 10,953 ms deterministic work,
16,229 ms summed wall time. Fabric's native response does NOT report billed cost:
**cost unavailable**, not zero. Failed development attempts are not included in
these successful/boundary receipt totals and may have incurred charges.

Every CLI receipt reports **Codex calls 0; generative worker calls 0**. The kernel
contains no model/worker launch operation, and mode guards are tested by attempting
all three generative stream methods. Slash-mode fixtures additionally assert normal
input is handled, tools/workers are blocked, provider outage does not fall through,
and generation is restored only by an explicit `/mode hybrid`.

## Observed generation boundary

E asks for checksum behavior (ABC → 198; Z → 90). The source returns literal zero;
there is no existing compatible expression or algorithm donor. The grammar cannot
introduce iteration/reduction or new logic. The result records phase, focused IDs,
evidence count, attempted families and missing capability, and stops with
NeedsGeneration. It does NOT produce a prose excuse or invoke a generative fallback.
J0 also correctly reaches NeedsGeneration on the operator task.

## Trace

Existing Alacritty rendering/protocol is untouched. Indexed candidate generation is
Search, dense policy lifetimes are Jev with head counts, mutations are Edit and exact
checks are Verify. NeedsGeneration is a failed enum/count Tool pulse; success is a
passed pulse. Pure input never starts a Codex agent/generation scope. No arbitrary
labels, excerpts, prompts, auth or results are sent to terminal IPC.

## Installation and direct mode probe

The verified package was added to the USER Nix profile at priority 4; the previous
priority-5 Pi runtime remains as fallback. Only Pi package/extension resource paths
were merged into writable settings, with a private settings backup. Auth files,
Fabric credential configuration and the Factory launcher were unchanged. No NixOS
or whole Home Manager activation occurred. Start a NEW Pi process, then `/mode jev`;
`/mode hybrid` is the explicit return, and `/jev-stop` cancels the finite task.
An already-running old process cannot acquire patched ModelRuntime imports via
extension reload alone.

## What is and is not established

Established: useful finite repairs selected by real Jev, exact environment
transitions, explicit missing-generation boundaries and zero host generative calls.
On this tiny ladder Jev used fewer repair attempts than the seeded random arm; the
simple heuristic matched its repair success and took less time. There is no evidence
here that Jev beats a good deterministic policy or reduces total cost versus Codex.
No frozen Sol A/B/C benchmark or general SWE-bench claim is made.

The earlier hybrid nested-write live probe remains conservatively denied: real
semantic sufficiency .53 and a diffuse risk distribution did not support a permit.
It made real host-owned Jev evaluations and did not bypass enforcement, but that is
NOT a successful hybrid live acceptance result. Deterministic batching, invalidation,
3/10 candidate admission, 1/3 worker admission, permits, provider failures, settlement
continuations and shell-denial fixtures pass. Hybrid context-admission benefit on a
real Sol task has not been established. Main's every generative turn is not vetoed by
the hybrid controller, and the separate information-gain selector is experimental.

Safety boundary: the host action grammar has no arbitrary shell action and checks
use fixed argv without API-key env variables. Repository tests still run with user
OS privileges (including HOME/network); malicious tests can execute external clients
outside Pi. This is NOT an adversarial repository sandbox. Unknown external extensions
are trusted host code. Cancellation is cooperative between macros/inflight Jev;
exact checks also have bounded process deadlines. Pure budgets are hard loop bounds,
not a general transaction/security system.

Kernel conclusion: a finite typed action language is enough for several genuinely
useful local coding behaviors without generative calls. The first clear grammar
boundary is **creating an algorithm that has no legal existing transformation or
donor**. That boundary, rather than a general-agent score, is this experiment's result.
