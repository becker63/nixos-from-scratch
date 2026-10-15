# Pure Jev playground: experimental report

The playground is implemented in
[`packages/pi-runtime/jev-playground`](../packages/pi-runtime/jev-playground/README.md).
The existing Jev kernel, grammar and policy are unchanged. No pinned inputs, kernel,
Factory missions, credentials, or system closures were changed. Nothing was published.

```text
Hybrid / Codex author
  → Generate
  → Admit with generic finite transforms + exact checks
  → Freeze workspace hashes / separate private oracle
  → Fresh pure Jev process
  → Exact scorer
```

## Architecture and isolation

The visible workspace contains only source, legitimate distractors and local/broad
checks. ChallengeSpec records task shape, grammar, difficulty, seed, budgets,
provenance, timestamp and hashes. The hidden oracle records expected targets,
successful legal edits or a two-edit witness, and admission results. Both manifest
and oracle stay outside the workspace. Pure requests contain no expected repair ID,
private target, admission result, or author conversation. Every policy starts from
an independent copy of the same frozen snapshot.

The child imports the unchanged kernel and the native Jev classifier client; it
loads no generative runtime or workers. Its transport only admits the resolved Jev
endpoint/model with finite Choice/Noul payloads. All recorded pure receipts report
**Codex calls = 0; worker calls = 0**. The final-runner smoke also records six real
classifier dispatches, zero denied/other dispatches, no oracle supplied, and no
loaded generative runtime. Existing tests independently deny all three Pi streaming
entry points in pure mode.

The final runner restricts exact-test filesystem access using Node permissions and
blocks test subprocesses/network. Automated tests attempt hidden-file reads, child
launches and network calls; all are denied. Scoring checks challenge/receipt/oracle
identity, independent exact results, and legal final file differences. Tampered tests
cannot produce a passing score. These are tested host capability boundaries, not an
adversarial OS sandbox claim. The original recovery/branching trials used trusted
factory-authored assertion-only tests before this final test restriction was added;
the separate smoke and multi-edit probe exercised the final restrictions.

Leakage tests reject answer filenames, repair comments, informative test names,
private identifiers in metadata/task text, and generator files in the workspace.
Token-aware scanning includes private edit IDs, final hashes and repair strings.
It detects obvious construction mistakes, not every possible semantic hint.

## Campaigns and schema

Implemented controls include file distractors through 64; symbol distractors through
32; variable alternatives through 64; operator, variable, callable and required
argument faults; misleading local evidence; broad-check traps; J0–J3 sweeps; prompt
variants over an unchanged snapshot; unsupported generation tasks; fixed read-only
`Symbol → ContainingFile → Tests`; and a two-successful-mutation probe. Author-supplied
bounded real-source mutations use the same admission mechanism. A content-free
curriculum function proposes difficulty changes without changing Jev policy/prompts.
No Sol/reference or hybrid fallback arm was added.

All single legal transforms are checked before admitting a normal repair. Boundary
proofs are scoped to that enumeration; arbitrary multi-edit impossibility is not
claimed. The supplied novel-algorithm task has zero legal target edits. The two-edit
probe proves that every single edit fails and that a generic pair passes. Admission
never consults a generative model about solvability.

## Recovery campaign

Five frozen Repair instances, seed 42, J2/J3, with 4–6 target-symbol legal edits.
Local and broad checks are independent. The strongest lexical candidate is not
marked correct, and policies receive no solution labels. These are single trials,
not repeated-trial probability estimates.

| Instance | Family / legal edits | Jev trajectory and outcome | Random | Heuristic |
| --- | --- | --- | --- | --- |
| 000 | Variable / 4 | Inspect → ambiguous Choice → premature NeedsGeneration; no mutation | Success, 8 mutations / 7 recovery reverts | Success, 2 / 1 |
| 001 | Callable / 6 | Inspect → correct edit leads distribution (.52), margin .05 → abstain → premature NeedsGeneration | Exhausted, 10 / 10 | Success, 3 / 2 |
| 002 | Argument / 4 | Insert existing `end` → local pass → broad pass → Success | Success, 7 / 6 | Success, 1 / 0 |
| 003 | Operator / 5 | `+` → `-` → local pass → broad pass → Success | Success, 7 / 6 | Success, 3 / 2 |
| 004 | Variable / 5 | `start` → `margin` → both checks pass → semantic finish refuses Success → cleanup rollback → premature NeedsGeneration | Success, 9 / 8 | Success, 3 / 2 |

Thus Jev solved **2/5**, random **4/5**, heuristic **5/5**. All five Jev runs classified
Repair correctly and reached the owning file/symbol; successful edits were generated
and remained in the finite Choice set. Recovery 004 is a **semantic finish failure**,
not a failed broad check or a failed repair. The recorder now snapshots observations;
older observation objects are scored from immutable exit statuses to avoid confusing
terminal rollback with a past test failure.

An additional final-runner smoke reran callable instance 001 and selected `distance`
directly: one mutation, both checks green, Success. It is reported separately and is
not folded into the five-instance trial. An earlier authoring probe also observed
callable recovery, but its receipt was overwritten before preservation of separate
reruns was implemented; it is excluded from quantitative tables. New reruns preserve
all receipts.

## Branching sweep and closed-loop recovery

Three instances per legal action count, same seed and budgets. Only variable
alternatives change; every declared repair exists in the actual grammar.

| Legal edits | Jev solved | Correct survived narrowing | Random solved | Heuristic solved |
| ---: | --- | --- | --- | --- |
| 4 | 2/3 | 3/3 | 3/3 | 3/3 |
| 8 | 0/3 | 3/3 | 1/3 | 3/3 |
| 16 | 0/3 | 2/3 | 0/3 | 1/3 |
| 32 | 0/3 | 1/3 | 0/3 | 1/3 |

Branching instance 001 demonstrates actual Jev recovery:

```text
Inspect compute
  → replace start with end
  → local PASS, broad FAIL
  → exact revert
  → replace start with probability
  → local PASS, broad PASS
  → Success
```

This is the requested wrong-edit → failed check → revert → alternate-edit → success
trajectory. The environment contains legitimate observational ambiguity; Jev was not
instructed to choose the wrong action. At 16/32 actions Jev often chooses a local-pass,
broad-fail edit and reverts it, then stops on a flat/unknown alternate distribution.
Verification prevents those trajectories from being counted as successful repairs.

Failure counts for Jev: recovery has three premature NeedsGeneration results
(two at Transform, one at Stop); branching has four premature NeedsGeneration,
three NarrowingFailure and three RecoveryFailure. No task classification, retrieval,
file or symbol selection failures occurred in these repair trials. Larger localization
and symbol campaigns are implemented but were not run; their relative failure onset
is still unknown. Random/heuristic larger-branch failures primarily exhaust budgets.

## Bounded real-source mutation

The generalized author API was exercised on the actual `shape()` definition from
`packages/pi-runtime/semantic-policy.ts`. Only the isolated subset received the
controlled `-` → `+` margin fault. Generic J2 admission found the legal passing repair
inside nine target edits; Jev used the ordinary relevance-narrowing stage. Jev and
heuristic solved with one mutation; seeded random solved with five mutations/four
reverts. Both exact checks passed. Recorded hashes prove the main source stayed
unchanged. This is a bounded real-source experiment, not a full-repository repair claim.

## Choice concentration

Every Choice distribution is retained, including classification/navigation and
non-enacted choices. Probability analysis distinguishes a chosen label from an action
actually executed, and distinguishes a passing single edit from eventual terminal
success. Examples from enacted choices:

| Instance / action | Top | Runner up | Margin | Unknown | Exact edit passes | Run succeeds |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| branching 001, first edit | .94 | .05 | .89 | .01 | No | Yes, after recovery |
| branching 001, alternate | .79 | .07 | .72 | .09 | Yes | Yes |
| branching 002 | 1.00 | .00 | 1.00 | .00 | Yes | Yes |
| recovery 004 | .68 | .29 | .39 | .00 | Yes | No, semantic finish veto |
| branching 010 | .79 | .10 | .69 | .02 | No | No |

A strongly concentrated wrong choice exists; high margin is not a correctness proof.
The sample is too small and confounded to infer calibration or a reliable predictive
relationship. Correct edit ranking can also coexist with abstention (recovery 001),
or exact repair success with a later semantic finish refusal (recovery 004).

## Generation boundary and composition

The novel checksum algorithm has no legal target transform. Jev returns
**CorrectNeedsGeneration**, zero mutations, in 1.53 s (1.01 s inference). Random and
heuristic also detect the boundary but spend five irrelevant mutations/reverts first.
A README-writing task returns **CorrectUnsupported** from Jev in .40 s, zero mutations
or checks. Baselines misclassify that task; their nominal Success is rejected by the
scorer.

Jev completes the fixed symbol/file/tests chain exactly, with zero mutations/checks;
classification and selection use real Jev. The two baselines return only a file, and
exact chain scoring rejects that incomplete result.

The two-edit instance requires `a+a` to become `b+c`. Deterministic admission proves
no single edit passes and a generic two-edit sequence does. Jev stops before mutation;
the heuristic tries seven individual edits and reverts every partial repair. The
unchanged controller demands a passing check after each individual mutation, so this
family exposes a partial-progress limitation. The playground reports it rather than
adding a special repair rule.

## Performance and evidence

| Campaign / arm | Generation¹ | Admission² | Jev inference | Other deterministic solve | Solve verification | Solver wall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| recovery / Jev, 5 | <1 ms | 12.58 s | 5.39 s | 2.63 s | 1.30 s | 9.34 s |
| recovery / random | shared | shared | 0 | 4.98 s | 5.87 s | 10.86 s |
| recovery / heuristic | shared | shared | 0 | 2.79 s | 2.87 s | 5.67 s |
| branching / Jev, 12 | 1 ms | 53.56 s | 16.71 s | 7.15 s | 3.09 s | 26.98 s |
| branching / random | shared | shared | 0 | 14.30 s | 17.05 s | 31.38 s |
| branching / heuristic | shared | shared | 0 | 13.43 s | 16.90 s | 30.36 s |

¹ Rounded workspace-materialization time from deterministic templates; zero generator
provider calls. Codex implementation/authoring conversation cost is outside this
measurement. ² Once per frozen set, not once per policy. Solver wall excludes fresh
process/kernel compilation overhead; raw receipt metrics are retained. Admission is
expensive relative to these tiny solves because it enumerates and verifies alternatives.

Recorded Jev usage: recovery 31,051 input / 5,143 output tokens; branching 150,282 /
23,252. These counts exclude earlier authoring probes, smoke/boundary/navigation and
multi-edit runs. Billed provider cost is unavailable. Full probability/Noul distributions,
trajectories, stage scores, hashes and budgets are in
[`results/`](../packages/pi-runtime/jev-playground/results/). Frozen workspaces and raw
request/response receipts remain in `.tmp/jev-playground/`; each campaign has Markdown
and JSON reports. The packaged result files include post-solve oracle comparisons;
they are never copied into a challenge workspace.

Validation passed: strict challenge-schema TypeScript; playground admission/leakage,
freeze, independent-run retention, transport, test capability, scoring-tamper and
rollback-snapshot tests; existing Jev fixtures/task tests; semantic controller and
trace tests; JS syntax and Nix expression parsing. No Nix system build/switch ran.

Generative intelligence can construct useful finite environments cheaply, and pure
Jev can select existing repairs, complete a finite navigation relation chain, detect
real generation boundaries, and sometimes recover from a wrong edit. This small sweep
shows **semantic action selection/abstention and final goal confirmation fail before
candidate recall**; narrowing and recovery add failures as branching grows. Keeping
multiple successful partial mutations is a separate architectural limitation. Exact
verification remains effective throughout. The deterministic heuristic is stronger
on these template families; these observations do not establish a Jev advantage.
