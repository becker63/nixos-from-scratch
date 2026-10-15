SWE-JS8 is a metadata-selected diagnostic slice of SWE-bench Multilingual. The existing pure Jev kernel is unchanged apart from its optional canonical-verifier seam. This is not an official benchmark score.

```text
Official metadata → frozen SWE-JS8 → exact upstream base checkout
                                          ↓
                      empty-patch failure + outer-only gold smoke
                                          ↓
                            fresh existing pure Jev child
                                          ↓
                         finite J3 actions → official grader
```

The adapter is `packages/pi-runtime/jev-playground/swe-mini.mjs`; `swe-verifier.mjs` calls the official single-instance evaluation API. No image recipes, test-log parsers, grading rules, synthetic tasks, or new agent are implemented.

Selection enumerates all 43 JS/TS tasks from the [official task repository](https://github.com/SWE-bench/swe-bench-multilingual-tasks) at `6e08cbcd763c869abd7aae4bcb9e1b3991180777`. Difficulty is the mean of repository-local min-max-normalized `log1p` gold changed lines, changed files, F2P count, and P2P count. Selection chooses the task closest to the interpolated median; Preact uses distinct 25th/75th-percentile choices. Ties use instance IDs. Gold patch semantics are not inspected for selection.

| Instance | Repository | Gold lines/files | F2P/P2P |
|---|---|---:|---:|
| babel__babel-14532 | babel/babel | 2 / 1 | 1 / 523 |
| vuejs__core-11915 | vuejs/core | 2 / 1 | 2 / 43 |
| facebook__docusaurus-8927 | facebook/docusaurus | 34 / 1 | 2 / 12 |
| immutable-js__immutable-js-2005 | immutable-js/immutable-js | 8 / 2 | 2 / 20 |
| mrdoob__three.js-26589 | mrdoob/three.js | 6 / 3 | 3 / 13 |
| axios__axios-4738 | axios/axios | 6 / 1 | 1 / 3 |
| preactjs__preact-3763 | preactjs/preact | 23 / 1 | 1 / 1 |
| preactjs__preact-3345 | preactjs/preact | 20 / 1 | 1 / 16 |

The frozen selection and outer receipts live in `packages/pi-runtime/jev-playground/results/swe-js8.json`. Gold metadata never enters Jev state.

The solver receives the original issue, a pristine isolated upstream checkout at `base_commit`, existing compiled kernel/dependencies, J3, and fixed limits: 24 steps, 32 evaluations, six transforms, two repeated states, and the existing 120-second agent wall limit. It receives no task directory, gold patch, hidden test patch, expected test lists, selection metadata, or verification command. The fresh child uses only the existing Jev classifier transport; no generative runtime or worker registry is imported. Its IPC request can ask only for canonical verification of the host-owned workspace.

Verification writes the current `git diff --binary HEAD` to a one-row predictions file with `instance_id`, `model_patch`, and `model_name_or_path: "pure-jev"`. Run IDs contain instance ID and full patch SHA256. [Official SWE-bench 5.0.2](https://github.com/SWE-bench/SWE-bench/tree/02e7a74ffd0b707aab73d203fe87bdc7c76afc8e) supplies task loading, containers, evaluation scripts, parsing, and F2P/P2P grading. Empty-patch reproduction uses its `skip_patch` API because the current CLI skips empty predictions. No implicit image pull/build is allowed in verification. Missing authoritative test statuses are infrastructure failures and never software evidence. Full reports remain outer-only; the child receives bounded failing names/status, passed, fingerprint, and an infrastructure flag. Canonical grading includes broad checks, so the kernel skips its duplicate broad Node verification. Default Node verification remains intact.

The runner prepares only the first selected task, with at most one same-repository fallback. Remaining tasks stay gated until empty reproduction fails, outer-only gold passes, and the pure child records Jev requests with zero Codex/worker calls. Images are prepared sequentially, pulls have a 180-second timeout, and less than 4 GiB free prevents a pull. `--release-images` releases only the exact task image after its attempt.

This Apple Silicon host has 16 KiB pages. Direct host QEMU could start the official AMD64 container but Node failed mapping its libraries. The already-installed Nix `muvm`/libkrun runtime provides a local ARM64 guest with 4 KiB pages; a private Docker daemon and guest-only static QEMU run the unmodified official image successfully. Node 20.20.2 was verified. Jev stays on the host; benchmark containers receive no classifier credentials. Host Docker, Factory processes, the host kernel, system generations, and all pinned inputs are preserved. No system closure is built or switched.

Local launchers and scratch disk are in `.tmp/swe-mini/muvm/`. With that private guest running, the current bounded attempt is:

```sh
PATH="$PWD/.tmp/swe-mini/muvm/bin:$PATH" \
DOCKER_HOST=tcp://127.0.0.1:2375 \
node packages/pi-runtime/jev-playground/swe-mini.mjs run \
  --selection packages/pi-runtime/jev-playground/results/swe-js8.json \
  --task-repo .tmp/swe-mini/task-repo \
  --python .tmp/swe-mini/muvm/bin/python \
  --output .tmp/swe-mini/nix-local-clean \
  --release-images --verification-timeout-seconds 600
```

The external canonical timeout defaults to 300 seconds; this local attempt fixes it at 600 seconds because the earlier official Babel run completed its development build but timed out in standalone bundling before tests. This changes only infrastructure timing, not the Jev grammar, policy, or budgets. The outer child watchdog allows the in-flight canonical call to finish; the existing agent wall budget remains authoritative afterward.

The bounded attempt is complete and frozen. Four tasks reached pure children; four slots remained BootstrapUnavailable after at most one same-repository fallback. No fallback reached a pure run. The first smoke passed: empty grading failed in 275.469 seconds; outer-only gold resolved in 271.269 seconds. Every pure child made Jev requests with zero Codex/worker calls, no supplied oracle or generative runtime, and the same compiled controller hash.

| Instance | Terminal | Official resolved | First failure | Jev inference | Canonical verification, all phases | Mutations/reverts |
|---|---|---|---|---:|---:|---:|
| babel__babel-14532 | Unsupported | false | TaskClassificationFailure | 0.609 s | 546.738 s | 0/0 |
| vuejs__core-11915 | BootstrapUnavailable | unknown | BenchmarkBootstrapFailure | — | 27.306 s | — |
| facebook__docusaurus-8927 | BootstrapUnavailable | unknown | BenchmarkBootstrapFailure | — | 27.764 s | — |
| immutable-js__immutable-js-2005 | NotFound | false | TaskClassificationFailure | 0.653 s | 56.328 s | 0/0 |
| mrdoob__three.js-26589 | NeedsGeneration | false | CandidateRecallFailure | 1.645 s | 46.161 s | 0/0 |
| axios__axios-4738 | NotFound | false | TaskClassificationFailure | 0.832 s | 27.757 s | 0/0 |
| preactjs__preact-3763 | BootstrapUnavailable | unknown | BenchmarkBootstrapFailure | — | 26.570 s | — |
| preactjs__preact-3345 | BootstrapUnavailable | unknown | BenchmarkBootstrapFailure | — | 31.858 s | — |

Verification includes outer reproduction and Babel's gold smoke. Pure-run verification was only three.js's cached reproduction (2.567 seconds); classification stopped the other children before verification. No duplicate broad evaluation ran.

The measured funnel is **8 selected → 4 pure runs → 3 retained a gold file → 0 inspected a gold file → 0 mutations → 0 resolved**. Four slots have no agent measurements. No exact one-transform gold match was established for the four analyzed tasks. Semantic grammar reachability and correct NeedsGeneration remain unestablished, not disproved.

Taxonomy: three TaskClassificationFailure, one CandidateRecallFailure, four BenchmarkBootstrapFailure slots. Babel's returned choice was Repair, but Repair and Inspect tied at 0.38 and kernel admission produced Unsupported. Immutable and Axios were classified Inspect and ended NotFound. Three.js was classified Repair and followed InspectFamily → InspectFile (`src/core/Object3D.js`) → InspectSymbol (`onRotationChange`) → NeedsGeneration. None of its three gold files appeared in the original frontier; it inspected none. That is retrieval evidence, not a proven novel-algorithm boundary. No policy or grammar was tuned.

Vue and its fallback crashed esbuild's Go runtime under QEMU before collecting tests. Docusaurus and its fallback crashed with QEMU target segmentation faults. Preact's selected instances encountered esbuild failures; the first fallback image pull failed, and the second could not launch Chrome. Infrastructure gaps are excluded from semantic-policy conclusions.

Recorded totals: checkout 46.532 seconds, successful image pulls 272.242 seconds, canonical verification 895.168 seconds across 13 calls, Jev inference 3.739 seconds, and agent deterministic work excluding verification 1.404 seconds. There were eight Jev evaluations, 40 heads, 17,491 input tokens, and 1,582 output tokens. Provider cost was not reported. Failed-pull time and post-hoc analysis are not assigned to these subtotals. No image builds, Sol arm, or full-suite preparation occurred.

On the runnable subset, **task interpretation fails first in three cases and candidate recall in one**. Action generation, narrowing, edit selection, recovery, and mutation verification were not reached deeply enough to measure. Post-hoc analysis encounters missing dependency/type diagnostics, further limiting reachability conclusions. This is four-task agent evidence with four environment gaps, not eight completed agent runs or an official score.

After each pure run ends, outer-only analysis compares gold-modified paths with the original 64-file frontier and inspected files. The unchanged J3 generator enumerates transforms on original gold-modified JS/TS source. An exact single-edit gold match is sufficient positive reachability evidence; absence of that match does not prove all semantically equivalent repairs impossible. Negative reachability remains unestablished. This analysis never changes the run or policy.

Timing receipts separate checkout, image preparation, Jev inference, deterministic agent work, and canonical verification. Earlier existing grammar, type, navigation, zero-generation, and canonical seam checks passed. Live grading remains a separate requirement.

Authorized ordinary `nix-store --gc` removed 532 unreferenced paths and freed 8.1 GiB. Trimming the private scratch filesystem brought host free space to approximately 17 GiB. No generations or profile roots were removed; `.tmp/swe-mini/nix-gc.log` records collection.

After the completed campaign, task image tags and evaluation containers were released. The private scratch filesystem was trimmed and only the private benchmark guest was stopped. Approximately 15 GiB remained free. Host Docker and Factory mission processes were preserved.
