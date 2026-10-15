# Pure Jev on SWE-JS8: pre-Atlas ablations

Conventional retrieval now exposes a gold-modified file for every runnable task. The final research agent reaches Immutable's `hashCollection` and Axios's `handleRequestTimeout`; its J4 enumerator still does not produce their required operations. Babel and three.js lose their gold files during Jev ranking. No task was officially resolved. Four of the eight environments remain unavailable on this platform. These are diagnostic single-run ablations, not an official SWE score or a demonstrated general ceiling.

## 1. Frozen baseline

Stage A is byte-for-byte unchanged in both `packages/pi-runtime/jev-playground/results/swe-js8.json` and `swe-js8-A-baseline.json`. SHA256: `0075351ed59054bae631e6dd08c9c84bfe5a35ffd34f247ff3f0c20a7e74d233`.

Exactly the original result: **8 selected → 4 pure runs → 3 retained a gold-modified file → 0 inspected a gold-modified file → 0 mutations → 0 officially resolved**. Babel: Unsupported/task classification. Immutable and Axios: NotFound/task classification. three.js: NeedsGeneration/candidate recall. Vue, Docusaurus and both Preact tasks: infrastructure blocked. Every pure child recorded Codex = 0, workers = 0, oracle supplied = false.

Original timings: Jev inference **3.739 s**; deterministic agent **1.404 s**; official verification **895.168 s**; image pulls **272.242 s**; checkout **46.532 s**. No baseline field or result has been replaced by a later interpretation.

The selection remains fixed; all gold statistics below are outer-only.

| Instance | Repository | Gold lines/files | F2P/P2P |
|---|---|---:|---:|
| babel__babel-14532 | babel/babel | 2/1 | 1/523 |
| vuejs__core-11915 | vuejs/core | 2/1 | 2/43 |
| facebook__docusaurus-8927 | facebook/docusaurus | 34/1 | 2/12 |
| immutable-js__immutable-js-2005 | immutable-js/immutable-js | 8/2 | 2/20 |
| mrdoob__three.js-26589 | mrdoob/three.js | 6/3 | 3/13 |
| axios__axios-4738 | axios/axios | 6/1 | 1/3 |
| preactjs__preact-3763 | preactjs/preact | 23/1 | 1/1 |
| preactjs__preact-3345 | preactjs/preact | 20/1 | 1/16 |

Selection SHA256: `3d1064cb51b32296acfd144ce2c7fa997fab717c591635fe5403e15de23c0458`. Every stage references it. See immutable receipts and `swe-js8-max-analysis-v2.json` for task/stage hashes and raw distributions. Gold inspection occurred in the outer process after the relevant pure child terminated.

## 2. Stage B: protocol routing and infrastructure

All four runnable tasks enter Repair and reproduce the existing authoritative empty-patch failure through an exact cache. The live task classifier remains a shadow: Babel Unsupported, Immutable Inspect, three.js Repair, Axios Inspect. Three of four shadow admissions disagree with the protocol fact. Axios reaches `lib/adapters/http.js`; the others do not reach a gold file. All four stop at NeedsGeneration, with zero mutations. Normal interactive task classification retains its existing behavior when no protocol override is supplied.

B.1 is a separate immutable infrastructure receipt, `swe-js8-B1-infrastructure.json`. The bounded attempt used the installed Nix FEX closure in the existing native ARM64 muvm/libkrun guest with 4 KiB pages; official x86 images, repository source and evaluation scripts remained unchanged. Node itself ran under FEX. All four blocked empty-patch evaluations still failed before authoritative grading:

| Task | Exact practical blocker | Empty canonical result | Gold check |
|---|---|---|---|
| Vue | esbuild Go runtime crash / stopped service | No authoritative test results | Not attempted after infrastructure failure |
| Docusaurus | process spawning: ENOMEM | No authoritative test results | Not attempted |
| Preact 3763 | spawning/esbuild/Karma infrastructure failure | No authoritative test results | Not attempted |
| Preact 3345 | Go fatal `unknown caller pc` / unexpected return PCs | No authoritative test results | Not attempted |

The attempt did not repair any of these environments. The baseline's guest-only QEMU runtime was restored for subsequent grading; Immutable's Stage D candidate was graded successfully as TaskFailure. No image was built, no repository test was weakened, no system closure was built/switched, and no pinned host kernel input was changed. Improving the remaining foreign Go/browser/runtime compatibility is still platform infrastructure work.

## 3. Stage C: conventional retrieval

The candidate compiler uses git-visible paths, bounded source text, sparse BM25 issue terms, path/identifier/code-span matches, diagnostic/test-name matches, AST definitions, relative imports including JS-to-TS source resolution, reverse imports, and test/source naming adjacency. It performs only bounded conventional searches and one-hop import/call facts. No Atlas, Attune, structural signatures, persistent graph or database exists. No dependency installation was performed in the upstream workspaces.

Up to 10,000 eligible tracked paths, 512 KiB/file, 96 KiB analyzed text/file and 96 MiB corpus text are admitted; source candidates with evidence are sorted deterministically and compressed to 256. Jev ranks bounded batches through 64 → 16 → 8. This is an explicit ceiling: oversized/excluded files, corpus limits and truncation can still lose evidence. Full project LSP/type configuration is **not** reconstructed; TypeScript parsing and available local checker facts are used. Package ownership does not have a separate implemented signal.

The first `C-retrieval` attempt sent 64-head/context batches and hit HTTP 400 in all four runs. That receipt remains immutable; it is a provider/request-shape failure. `C-retrieval-bounded` reduces batches to 16 and preserves that correction as a separate receipt. This is the valid Stage C comparison below.

| Task | Sources firing on gold files | Generated | Deterministic 256 | First Jev compression | Final Jev narrowing | Inspected |
|---|---|---|---|---|---|---|
| babel__babel-14532 | issue-token, path, identifier | true | true | false | false | false |
| immutable-js__immutable-js-2005 | issue-token, identifier, code-span, import | true | true | true | false | false |
| mrdoob__three.js-26589 | issue-token, path, identifier, code-span, import | true | true | true | false | false |
| axios__axios-4738 | issue-token, path, identifier, test-adjacency, import | true | true | true | false | false |

The correct source file is generated and retained for all four runnable tasks, including three.js. None survives final semantic narrowing in this Stage C run. Candidate compilation and semantic ranking failures are therefore separated. Changelog-only changes are not treated as executable repair locations.

## 4. Stage D: finite J4

J4 adds existing compatible literal replacement, boolean operator alternatives, unary negation, broader equality/comparison replacements, compatible object members, argument replacement/removal/permutation, existing return-expression and condition donors. J3 callable replacements and compiler single-file fixes remain available. Return/condition donors are confined to the same owning function with in-scope references; literals are bounded existing file literals. Nearby-test donor harvesting and project-wide language-service setup are not implemented.

Every admitted edit has a matching original span and provenance: AST donor span, TypeChecker source site, or compiler fix. Candidate source must parse. The source-local diagnostic **multiset by code/message must not worsen**, ignoring shifted offsets; unknown/any types do not certify donor/member/argument compatibility. This permits existing missing-import or strict-JS diagnostics while rejecting new ones. It does not prove project-wide type correctness, and compiler fixes can address diagnostics unrelated to the issue. Exact grading remains authoritative.

Raw enumeration is capped at 128 candidates and legal output at 64 per focused site. No arbitrary expression, branch, loop, binding, import or algorithm synthesis was added.

| Task | Closest gold operation | Current evidence |
|---|---|---|
| Babel | new imported predicate plus condition disjunct | Outside the enumerated J4 construction families |
| Immutable | replace `size` argument with existing-object member `collection.size` | J4-shaped; required expression not emitted by current typed/in-scope argument enumeration. Changelog and unused-binding changes make whole-gold equality too strict as a behavioral oracle |
| three.js | new conditional assignment at three copy sites | Assignment-expression construction is unavailable; three sites also exceed the run's two-edit depth |
| Axios | introduce message binding and conditional override | Binding/statement construction unavailable |
| Vue | add an existing-state guard | Could only fit a condition donor if the complete applicable expression already exists in scope; unestablished, environment blocked |
| Docusaurus | regex/parser rewrite | New regex/binding/replacement logic unavailable; environment blocked |
| Preact 3763 | relocate/duplicate callback loop and reset | Statement movement/duplication unavailable; environment blocked |
| Preact 3345 | restructure cleanup/catch and introduce bindings | Statement/exception-flow construction unavailable; environment blocked |

Post-hoc J4 enumeration in gold files produces legal alternatives, but no exact whole-gold single-edit match. **No match is not proof that every semantically equivalent passing patch is impossible.** We do not count any task as conclusively CorrectNeedsGeneration from that negative result alone.

Stage D observes one mutation: Immutable chooses `src/OrderedSet.js/of` and compiler fix `this(arguments) → new this(arguments)`. Official grading fails both relevant hash behavior checks; the exact snapshot is reverted. This is a repair at the wrong semantic site, despite a concentrated edit Choice.

## 5. Stage E: bounded transactions

The transaction tracks base revision, edit IDs/families, changed files and exact before/after snapshots. Each application repeats source-span and cheap syntax/non-worsening-diagnostic gates. Legal moves include ContinuePatch, VerifyPatch, RollbackLast and RollbackPatch. Two unverified edits are used in the experiments; the same bounded implementation accepts depth three when explicitly configured. No combinatorial bundle search or unbounded planner was added.

Unit checks cover two files, deferred checks, depth enforcement, last/full rollback, stable base revision and refusal to overwrite an external mutation. Existing single-edit behavior and verification guards still pass.

No real two-edit transaction is observed in SWE-JS8. Stage E repeats Immutable's one compiler mutation, then abstains at continuation; terminal cleanup restores it without canonical grading. This cannot establish multi-edit semantic policy competence. The raw trajectory and rollback metrics are preserved.

## 6. Stage F: verification-aware Jev-max

Research mode may return bounded canonical failures during solving. Benchmark-faithful mode exposes only host-owned syntax/source-local diagnostic gates; the final patch is graded **once after the child terminates**. Cheap pass can produce Submitted, never exact Success. No repository-specific visible test commands are automatically installed or run in this version.

Canonical cache identity is instance + exact patch SHA256 + official script/task definition + supplied grader/runtime/image identity. New evaluations use the inspected image ID and official harness version/task commit. Infrastructure failures are not reused as software truth. Legacy authoritative baseline empty-patch receipts are explicitly imported with their source receipt, rather than relabeled as fresh evaluations. With an unchanged empty final patch, the final canonical invocation reads that existing exact result and incurs no container execution.

Five bounded Noul heads estimate patch completeness, utility of another edit, informativeness of verification, regression risk and rollback preference. They can schedule a check or continuation, and cannot establish Success. The measured SWE runs do not reach an active patch in Stage F, so **their information-value behavior is not empirically validated**. Zero new grading calls here mostly reflects zero mutations.

F also uses batches of eight, richer bounded issue/source facts, and preserves deterministic top-eight retrieval anchors beside eight semantic candidates. Therefore F is a combined policy/budget/verification improvement, not a pure scheduling-only ablation. It allows 96 evaluations and 48 steps; tests remain scarce. Canonical waiting is excluded from its agent-work wall budget.

Two separately frozen supplements address discovered conventional/controller limits:

- `F-jev-max-exploration`: local edit abstention can relocalize within the finite retained files; six-file cap. Flat-choice counts reset after an accepted move.
- `F-jev-max-exploration-facts`: enumerate up to 512 named symbols, include named function expressions, deterministically retain 64 by issue terms and one-hop existing calls. This fixes the old cutoff before Immutable's `hashCode`/`hashCollection` and the omission of Axios's named timeout callback. Evaluation cap is 128; no J4 family changes.

The final research supplement reaches both gold functions but produces no useful matching repair. The same final implementation is then run in benchmark-faithful mode with hidden grading withheld until termination. Each supplement keeps its own immutable receipt; none overwrites A–F.

| Final research task | Generated | Retained | Ranked | Gold file inspected | Gold symbol inspected | First failing stage |
|---|---|---|---|---|---|---|
| babel__babel-14532 | true | true | false | false | false | JevLocalizationFailure |
| immutable-js__immutable-js-2005 | true | true | true | true | true | EditEnumerationFailure |
| mrdoob__three.js-26589 | true | true | false | false | false | JevLocalizationFailure |
| axios__axios-4738 | true | true | true | true | true | EditEnumerationFailure |

| Benchmark-faithful task | Terminal | First failing stage | Gold file inspected | Gold symbol inspected | Mutations/reverts | Resolved |
|---|---|---|---|---|---|---|
| babel__babel-14532 | Exhausted | JevLocalizationFailure | false | false | 0/0 | false |
| vuejs__core-11915 | BootstrapUnavailable | InfrastructureFailure | — | — | 0/0 | false |
| facebook__docusaurus-8927 | BootstrapUnavailable | InfrastructureFailure | — | — | 0/0 | false |
| immutable-js__immutable-js-2005 | NeedsGeneration | JevLocalizationFailure | false | false | 0/0 | false |
| mrdoob__three.js-26589 | Exhausted | JevLocalizationFailure | false | false | 0/0 | false |
| axios__axios-4738 | Exhausted | EditEnumerationFailure | true | true | 0/0 | false |
| preactjs__preact-3763 | BootstrapUnavailable | InfrastructureFailure | — | — | 0/0 | false |
| preactjs__preact-3345 | BootstrapUnavailable | InfrastructureFailure | — | — | 0/0 | false |

## 7. Stage comparison and funnel

All rows use the same eight selected instances. Counts refer to the four runnable tasks; blocked tasks remain in the denominator of eight. “—” means that the earlier receipt did not record that subdivision. Candidate retention counts a gold-modified source file, not successful patch reachability.

| Stage | Runnable | Repair | Gold generated | Gold retained | Gold ranked | Gold file inspected | Gold symbol inspected | Mutation tasks | Resolved |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A-baseline | 4 | 1 | — | 3 | — | 0 | 0 | 0 | 0 |
| B-protocol | 4 | 4 | — | 3 | — | 1 | 0 | 0 | 0 |
| C-retrieval-bounded | 4 | 4 | 4 | 4 | 0 | 0 | 0 | 0 | 0 |
| D-j4 | 4 | 4 | 4 | 4 | 0 | 0 | 0 | 1 | 0 |
| E-patchsets | 4 | 4 | 4 | 4 | 2 | 1 | 0 | 1 | 0 |
| F-jev-max | 4 | 4 | 4 | 4 | 2 | 1 | 0 | 0 | 0 |
| F-jev-max-exploration | 4 | 4 | 4 | 4 | 2 | 2 | 0 | 0 | 0 |
| F-jev-max-exploration-facts | 4 | 4 | 4 | 4 | 2 | 2 | 2 | 0 | 0 |
| F-jev-max-exploration-facts-faithful | 4 | 4 | 4 | 4 | 2 | 1 | 1 | 0 | 0 |

Final research funnel:

```json
{
  "selected": 8,
  "runnable": 4,
  "repair": 4,
  "generated": 4,
  "retained": 4,
  "ranked": 2,
  "inspected": 2,
  "symbolInspected": 2,
  "goldOperationEnumerablyEstablished": 0,
  "usefulEditEstablished": 0,
  "mutationTasks": 0,
  "patchSubmitted": 0,
  "resolved": 0
}
```

Gold operation/repair-candidate reachability is **unestablished**, rather than an exhaustive zero-probability assertion. No useful gold-like edit has been demonstrated by these enumerations; no submitted mutation resolves an instance. The first C HTTP-400 attempt is excluded from this comparison and remains available for audit.

## 8. Positive controls

No additional task was bootstrapped or run. A cheap post-hoc look at existing small-patch metadata/gold diffs found many new guards, regex edits, optional chaining and statement movement; small line count alone did not establish J4 reachability. A validated **GRAMMAR-SCREENED POSITIVE CONTROL, NOT REPRESENTATIVE** cohort was not established. We consequently cannot infer real-task selection accuracy conditional on a known reachable successful patch. Existing unit checks validate mechanics, not that research question.

## 9. Failure decomposition and Choice diagnostics

Final benchmark-faithful first failing stages:

```json
{
  "JevLocalizationFailure": 3,
  "InfrastructureFailure": 4,
  "EditEnumerationFailure": 1
}
```

Terminal Exhausted and the six-file budget are recorded separately from the first observed pipeline failure. All four environment failures remain InfrastructureFailure. Retrieval source failures, deterministic compression failures, semantic localization, symbol enumeration/selection, edit enumeration/selection, composition/recovery, cheap/canonical verification, premature abstention, provider failure and budget exhaustion are distinct diagnostic concepts. A passing finite candidate must be established before labeling JevEditSelectionFailure for rejection of a *correct* repair.

Important Choices retain top, runner-up, margin, unknown, selected/executed ID and subsequent check status in structured analysis; all raw response distributions remain in stage receipts. Examples:

| Stage/task | Executed action | Top | Runner-up | Margin | Unknown | Later evidence |
|---|---|---:|---:|---:|---:|---|
| B-protocol / axios__axios-4738 | InspectFile | 0.71 | 0.15 | 0.56 | 0.01 | gold file selected; action unverified |
| D-j4 / immutable-js__immutable-js-2005 | ApplyEdit | 0.87 | 0.07 | 0.80 | 0.07 | false |
| E-patchsets / immutable-js__immutable-js-2005 | ApplyEdit | 0.85 | 0.07 | 0.78 | 0.07 | unverified |
| E-patchsets / axios__axios-4738 | InspectFile | 0.68 | 0.22 | 0.46 | 0.01 | gold file selected; action unverified |
| F-jev-max / axios__axios-4738 | InspectFile | 0.63 | 0.22 | 0.41 | 0.00 | gold file selected; action unverified |
| F-jev-max-exploration / immutable-js__immutable-js-2005 | InspectFile | 0.48 | 0.21 | 0.27 | 0.01 | gold file selected; action unverified |
| F-jev-max-exploration / axios__axios-4738 | InspectFile | 0.63 | 0.18 | 0.45 | 0.00 | gold file selected; action unverified |
| F-jev-max-exploration-facts / immutable-js__immutable-js-2005 | InspectFile | 0.47 | 0.27 | 0.20 | 0.01 | gold file selected; action unverified |
| F-jev-max-exploration-facts / axios__axios-4738 | InspectFile | 0.79 | 0.10 | 0.69 | 0.00 | gold file selected; action unverified |
| F-jev-max-exploration-facts-faithful / axios__axios-4738 | InspectFile | 0.83 | 0.12 | 0.71 | 0.01 | gold file selected; action unverified |

The final research symbol Choices agree with the executed IDs: Immutable `hashCollection` has top 0.82, margin 0.73; Axios `handleRequestTimeout` has top 0.99, margin 0.98. These are correct symbol-localization decisions followed by no matching repair candidate, rather than evidence of bad edit selection. File actions may include deterministic fallback; selected and executed IDs are both retained in JSON.

The Stage D edit has top 0.87, runner-up 0.07, margin 0.80, unknown 0.07 and still fails exact grading. Only one live mutated patch received a new canonical result in these ablations. There is no evidence for calibration or a reliable margin/success curve. File agreement with gold is a post-hoc localization proxy, not a passing repair.

## 10. Performance and mutation efficiency

Seconds; the AST and candidate columns are subdivisions of deterministic work, **not additional costs to sum**. The candidate timer covers the recorded frontier compilation and post-reproduction compilation; initial world construction/compilation and runtime initialization remain in other deterministic work. AST/type timing comes from prepare/apply traces when available; “—” is not instrumented. Earlier totals lack those subdivisions. A uses its original reported deterministic metric; B onward uses solver wall minus Jev and verification waiting, so runtime initialization is included. Canonical time counts official wall time; later direct cache hits cost no new grading. A retains its original full 895.168-second total, including baseline smoke/infrastructure attempts and Python cache-wrapper overhead. Raw JSON contains heads and token totals; provider dollar cost is not reported by Jev.

| Stage | Checkout | Jev | Recorded retrieval | Recorded AST/type | Total deterministic agent | Cheap checks | Official canonical wall | Noncached/logical canonical calls |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A-baseline | 46.53 | 3.74 | — | — | 1.40 | 0.00 | 895.17 | 12/13 |
| B-protocol | 43.57 | 4.38 | — | — | 8.38 | 0.00 | 0.00 | 0/4 |
| C-retrieval-bounded | 52.15 | 15.01 | 4.02 | — | 16.40 | 0.00 | 0.00 | 0/4 |
| D-j4 | 33.30 | 16.70 | 4.02 | — | 24.80 | 0.00 | 61.70 | 1/5 |
| E-patchsets | 39.60 | 16.27 | 4.01 | — | 25.08 | 0.00 | 0.00 | 0/4 |
| F-jev-max | 37.75 | 31.06 | 4.01 | 11.72 | 26.10 | 0.00 | 0.00 | 0/4 |
| F-jev-max-exploration | 31.55 | 34.28 | 3.98 | 14.95 | 29.26 | 0.00 | 0.00 | 0/4 |
| F-jev-max-exploration-facts | 38.04 | 56.33 | 5.41 | 84.20 | 102.67 | 0.00 | 0.00 | 0/4 |
| F-jev-max-exploration-facts-faithful | 81.60 | 50.74 | 4.49 | 24.30 | 40.81 | 0.22 | 0.00 | 0/4 |

Final research solver-work shares (recorded retrieval is a lower bound, remaining initialization is assigned to other deterministic work): jevMs: 35.4%; candidateKnownMs: 3.4%; astTypeMs: 53.0%; otherDeterministicMs: 8.2%; cheapVerificationMs: 0.0%; canonicalMs: 0.0%. This excludes checkout, outer post-hoc gold analysis and image bootstrap. The original A image pull cost remains 272.242 seconds (outside the timing table); B.1's additional environment work is separately receipted. D's image preparation was not separately instrumented and must not be inferred from canonical time. F prepares an image lazily only for a noncached candidate; its raw bootstrap record identifies reuse/pull and image ID.

Canonical calls per task, mutations/reverts, Jev calls and timings are in `swe-js8-max-analysis-v2.json`. No physical canonical call occurs in F; Jev-calls/physical-verification and time-to-first-new-verification are therefore undefined there. Stage D performs one physical check after its single mutation. The observed reduction in grading is not evidence of improved repair accuracy.

Per task/stage (seconds):

| Stage / instance | Checkout | Jev | Recorded retrieval | AST/type | Total deterministic | Cheap verification | Canonical |
|---|---:|---:|---:|---:|---:|---:|---:|
| A-baseline / babel__babel-14532 | 2.44 | 0.61 | — | — | 0.00 | 0.00 | 546.74 |
| A-baseline / immutable-js__immutable-js-2005 | 0.59 | 0.65 | — | — | 0.12 | 0.00 | 56.33 |
| A-baseline / mrdoob__three.js-26589 | 33.83 | 1.65 | — | — | 1.22 | 0.00 | 43.62 |
| A-baseline / axios__axios-4738 | 0.50 | 0.83 | — | — | 0.06 | 0.00 | 27.76 |
| B-protocol / babel__babel-14532 | 1.88 | 1.17 | — | — | 2.92 | 0.00 | 0.00 |
| B-protocol / immutable-js__immutable-js-2005 | 0.60 | 1.03 | — | — | 1.75 | 0.00 | 0.00 |
| B-protocol / mrdoob__three.js-26589 | 40.24 | 1.07 | — | — | 2.30 | 0.00 | 0.00 |
| B-protocol / axios__axios-4738 | 0.84 | 1.11 | — | — | 1.41 | 0.00 | 0.00 |
| C-retrieval-bounded / babel__babel-14532 | 1.84 | 4.50 | 1.24 | — | 8.27 | 0.00 | 0.00 |
| C-retrieval-bounded / immutable-js__immutable-js-2005 | 0.57 | 3.49 | 0.33 | — | 1.63 | 0.00 | 0.00 |
| C-retrieval-bounded / mrdoob__three.js-26589 | 49.22 | 4.17 | 2.26 | — | 5.72 | 0.00 | 0.00 |
| C-retrieval-bounded / axios__axios-4738 | 0.51 | 2.85 | 0.19 | — | 0.78 | 0.00 | 0.00 |
| D-j4 / babel__babel-14532 | 2.38 | 4.67 | 1.30 | — | 7.26 | 0.00 | 0.00 |
| D-j4 / immutable-js__immutable-js-2005 | 1.06 | 4.29 | 0.34 | — | 3.65 | 0.00 | 61.70 |
| D-j4 / mrdoob__three.js-26589 | 29.09 | 4.87 | 2.19 | — | 13.08 | 0.00 | 0.00 |
| D-j4 / axios__axios-4738 | 0.77 | 2.87 | 0.19 | — | 0.82 | 0.00 | 0.00 |
| E-patchsets / babel__babel-14532 | 2.16 | 4.78 | 1.24 | — | 7.09 | 0.00 | 0.00 |
| E-patchsets / immutable-js__immutable-js-2005 | 0.67 | 3.68 | 0.33 | — | 2.54 | 0.00 | 0.00 |
| E-patchsets / mrdoob__three.js-26589 | 35.98 | 4.75 | 2.24 | — | 13.25 | 0.00 | 0.00 |
| E-patchsets / axios__axios-4738 | 0.79 | 3.06 | 0.20 | — | 2.20 | 0.00 | 0.00 |
| F-jev-max / babel__babel-14532 | 1.99 | 7.99 | 1.24 | 0.85 | 8.19 | 0.00 | 0.00 |
| F-jev-max / immutable-js__immutable-js-2005 | 0.67 | 8.05 | 0.35 | 1.06 | 2.33 | 0.00 | 0.00 |
| F-jev-max / mrdoob__three.js-26589 | 34.06 | 10.31 | 2.23 | 8.46 | 13.40 | 0.00 | 0.00 |
| F-jev-max / axios__axios-4738 | 1.03 | 4.70 | 0.19 | 1.36 | 2.18 | 0.00 | 0.00 |
| F-jev-max-exploration / babel__babel-14532 | 1.87 | 8.02 | 1.22 | — | 7.18 | 0.00 | 0.00 |
| F-jev-max-exploration / immutable-js__immutable-js-2005 | 0.91 | 7.21 | 0.35 | — | 1.26 | 0.00 | 0.00 |
| F-jev-max-exploration / mrdoob__three.js-26589 | 28.00 | 13.48 | 2.20 | 13.52 | 18.54 | 0.00 | 0.00 |
| F-jev-max-exploration / axios__axios-4738 | 0.77 | 5.57 | 0.20 | 1.43 | 2.28 | 0.00 | 0.00 |
| F-jev-max-exploration-facts / babel__babel-14532 | 1.75 | 14.14 | 1.21 | 50.33 | 58.32 | 0.00 | 0.00 |
| F-jev-max-exploration-facts / immutable-js__immutable-js-2005 | 0.78 | 11.07 | 0.58 | 12.05 | 14.15 | 0.00 | 0.00 |
| F-jev-max-exploration-facts / mrdoob__three.js-26589 | 34.73 | 19.78 | 3.42 | 11.41 | 18.56 | 0.00 | 0.00 |
| F-jev-max-exploration-facts / axios__axios-4738 | 0.77 | 11.34 | 0.19 | 10.41 | 11.64 | 0.00 | 0.00 |
| F-jev-max-exploration-facts-faithful / babel__babel-14532 | 1.81 | 12.37 | 1.27 | 1.10 | 8.81 | 0.17 | 0.00 |
| F-jev-max-exploration-facts-faithful / immutable-js__immutable-js-2005 | 0.82 | 6.88 | 0.37 | 0.60 | 1.88 | 0.01 | 0.00 |
| F-jev-max-exploration-facts-faithful / mrdoob__three.js-26589 | 78.32 | 20.27 | 2.67 | 12.27 | 18.61 | 0.01 | 0.00 |
| F-jev-max-exploration-facts-faithful / axios__axios-4738 | 0.65 | 11.22 | 0.18 | 10.34 | 11.51 | 0.03 | 0.00 |

Outer post-hoc analysis is excluded from agent inference and verification timing. It can be substantial because it invokes the generic enumerator in gold files. Cache replay is reported separately from a newly executed official evaluation.

## 11. Pre-Atlas ceiling

The agent has moved from mostly irrelevant task admission failures to reliable Repair routing, source-file recall in all runnable repositories, and actual function localization in two real issues. A richer finite language emits legal local changes and a transaction controller supports bounded composition mechanically. The representative slice still yields **0/4 runnable resolved, with four additional infrastructure-blocked tasks**.

The first remaining operational failure is **Jev localization/narrowing for Babel and three.js**, and **edit enumeration/grammar scope after correct symbol selection for Immutable and Axios in the final research run**. Benchmark-faithful results differ and are reported separately; one run per stage does not isolate sampling variance. Composition and verification scheduling are implemented but lack a real successful/multi-edit trajectory. CorrectNeedsGeneration is not proven merely by not finding a repair.

Dominant remaining categories for runnable tasks, using the requested A–F ceiling categories: **B for all four, provisionally**—their correct locations are exposed in the candidate union, but the required gold operations are absent from the current grammar/enumerator. For Babel and three.js, this is an ultimate language limitation, not their first observed failure; their immediate failure remains semantic location selection. We cannot assert category C (a correct repair candidate exists but is selected badly), because no correct repair candidate has been established. We also cannot assert genuinely novel generation is necessary: richer finite donor/statement grammars might express some of these changes. Blocked tasks are **E**, environment limitations.

Without Atlas, the next concrete work would be issue-focused policy representations/ranking, better conventional type context for donor expression enumeration, and a validated small real positive-control cohort. Then consider bounded existing-expression/statement composition. Adding operators blindly will not address incorrect file selection, and storing more repository structure will not create a missing expression/branch by itself.

## 12. Atlas decision evidence and isolation

There is **no strong evidence that Atlas is the next required abstraction**. After conventional retrieval, source candidate recall is 4/4. Babel's correct file is present but low-ranked; three.js's Line/Mesh/Points files are present but Jev favors Object3D and unrelated examples. An inheritance/copy-family representation could be a hypothesis to test for three.js, but this run does not separate its value from better conventional ranking. The previously missing Immutable/Axios symbol facts were fixed with ordinary AST enumeration and local calls, without structural machinery.

Policy and finite language coverage have stronger concrete evidence than a structural candidate-compiler deficiency. Atlas alone would not express the missing conditional assignments, new message binding/guard or imported disjunct. No Atlas design or implementation is introduced here.

The pure child imports the existing finite kernel and classifier-only transport. It has no generative worker registry or model runtime. The transport accepts only the configured finite classifier endpoint/model with finite heads; generation dispatch is blocked. Tests exercise all three Pi stream entry-point guards. The outer adapter asserts child and kernel Codex/worker counters are zero. Every pure run records a fresh PID and `oracleSupplied:false`; the solver receives original issue, exact base repository and finite options, never task directory, gold patch, test patch, gold metadata or scoring targets. Gold post-hoc operations occur after the relevant child closes. Faithful runs contain only cheap verification events and no hidden canonical failure names.

The benchmark container receives neither Jev credentials nor the classifier process. Host source workspaces remain isolated and are removed after scoring. Official `load_task`/`run_instance`/grading are authoritative; no test-log parser or alternate grader is implemented. No host pins/system closure, credentials, Factory process or unrelated working-tree change was modified; nothing was pushed or published.

The owned evaluation guest has been stopped and 3.1 GiB of unused space in its scratch filesystem trimmed. The existing Factory mission remains running. Cached images and all experiment artifacts are retained.

To start the existing private guest in one terminal (no system build/switch):

```sh
muvm --mem=4096 --gpu-mode=software --interactive --privileged \
  -x "$PWD/.tmp/swe-mini/muvm/start-docker.sh" \
  -- /run/current-system/sw/bin/sleep 10800
```

In a second terminal, register the already-cached guest-only QEMU interpreter before grading. These runtime helpers remain in the isolated scratch directory; they are not a second task sandbox or grader.

```sh
.tmp/swe-mini/muvm/bin/docker run --pull=never --privileged --rm \
  tonistiigi/binfmt:qemu-v10.0.4-56 --install amd64
```

Then rerun with a new immutable variant identifier:

```sh
PATH="$PWD/.tmp/swe-mini/muvm/bin:$PATH" \
node packages/pi-runtime/jev-playground/swe-mini.mjs stage \
  --stage F --variant jev-max-exploration-facts-NEW \
  --verification-mode benchmark-faithful \
  --python .tmp/swe-mini/muvm/bin/python \
  --output .tmp/swe-mini/NEW
```

The adapter rejects an existing receipt/output snapshot. The variant's `exploration` and `facts` switches are explicitly recorded in the receipt (six-file exploration and 128 evaluations); the selected tasks are never regenerated. Research is the default verification mode. Default interactive kernel use retains its Node verifier and optional features remain opt-in.

Validation: strict TypeScript and existing kernel fixtures pass, including protocol routing, J4 provenance/non-worsening diagnostics, named callbacks/large symbol inventory, bounded transaction rollback/external mutation protection, and cheap Submitted versus canonical Success. The exact cache test checks patch, environment and task-definition isolation without running Docker/Python.
