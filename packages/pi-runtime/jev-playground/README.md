# Jev playground

A local task factory for the existing pure Jev kernel. This is an experiment, not a
benchmark. The kernel, action grammar and policy are imported unchanged.

```text
Hybrid / Codex (environment author)
  → generate bounded files or propose a controlled source mutation
  → deterministic admission using the actual generic transform enumerator
  → freeze visible file hashes + write a separate private oracle
  → fresh pure Jev process (no model runtime, worker registry or conversation)
  → exact scorer
```

Run from the repository root:

```sh
node packages/pi-runtime/jev-playground/cli.mjs generate recovery --count 5 --seed 42 --out .tmp/arena/recovery
node packages/pi-runtime/jev-playground/cli.mjs run recovery --out .tmp/arena/recovery
node packages/pi-runtime/jev-playground/cli.mjs campaign branching-scale --count 3 --out .tmp/arena/branching
npm --prefix packages/pi-runtime run test:playground
```

The packaged wrapper is `pi-jev-playground`. Source execution can use
`PI_PLAYGROUND_RUNTIME=/path/to/installed/pi-runtime` for immutable dependencies;
otherwise it uses local node_modules or the installed Pi wrapper. No dependency
installation, NixOS closure, profile activation or system switch is needed.

`generate` includes **admit → freeze**. `run` reuses frozen instances and runs the
three policies sequentially. `--policies jev`, `random`, or `heuristic` limits arms.
Every rerun gets another receipt directory; existing receipts are preserved. Prompt
variants share the same canonical snapshot and receive independent mutable copies.

## Files and visibility

An instance contains:

- `workspace/`: source, legitimate distractors and exact local/broad tests only.
- `private/manifest.json`: typed ChallengeSpec, difficulty, budgets, seed, provenance,
  timestamp, visible hashes and oracle hash. Not sent to the evaluator.
- `private/oracle.json`: expected terminal, target, every admitted successful edit,
  test outcomes, exact expected navigation relations and admission proof scope. Not sent to the solver child.
- `runs/`: independent workspaces, raw evaluator requests/responses, terminal receipts
  and exact scores. Only the scorer reads the oracle, after a terminal receipt.

See `spec.ts`. Workspace hash is SHA-256 of the sorted path/content-hash manifest.
Every regular visible file is included; symlinks and nonregular files are rejected.
The canonical files are read-only, and hashes are asserted before/after solving.
The runner passes only task, grammar, policy, seed, budgets and the mutable workspace
path to the unchanged kernel. A navigation relation chain is a separate finite host
operation. No hidden expected target or repair ID enters its context or Jev requests.

The child loads no generative runtime, tools, extension registry, skills, author or
scorer. Its one provider transport accepts only the resolved Jev endpoint/model and
finite Choice/Noul requests; chat/generation and worker payloads are denied before
dispatch. The credential launcher is preserved. Checks receive no API keys. The final
runner uses Node permissions to restrict test reads to the workspace/runtime modules,
deny subprocesses, and disable network through a fixed preload. Hidden-oracle reads,
network, subprocess attempts and redirected/nonclassifier provider requests are tested.
These are host capability controls, not a claim of an adversarial OS security sandbox.

Scoring independently runs both checks, verifies frozen challenge/oracle/receipt
identity, and checks that final file differences correspond to recorded legal edits.
Changing test files cannot manufacture a passing score. Generators and private
metadata cannot be placed in the visible workspace. Leakage scanning covers filenames,
comments, test names, task text and visible metadata, including exact private edit IDs,
final hashes and repair strings with sensible token boundaries. This catches obvious
leaks; it does not prove the absence of semantic hints in a challenge.

## Admission and authoring

For repair instances: reproduce failure, enumerate actual J0–J3 legal transformations
in every bounded source file, and try each in a private author workspace against local
and broad checks. Admit a solvable instance only with an exact passing witness.
Boundary admission requires no successful enumerated single transform. The supplied
novel-algorithm and J0/J1 boundaries also have no legal target edits; their limitation
is stronger than merely failing a one-edit search. Admission artifacts label their
scope explicitly; arbitrary multi-edit unsolvability is not asserted.

The two-edit family exhausts single edits, then finds a generic two-transform witness
before freeze. This exposes the existing controller's inability to retain a partial
repair that still fails verification. The playground does not change that behavior.

Hybrid authors can submit bounded real-source proposals through the same admission:

```sh
node packages/pi-runtime/jev-playground/cli.mjs generate source --proposal /tmp/proposal.json --out .tmp/arena/source
node packages/pi-runtime/jev-playground/cli.mjs run instance --out .tmp/arena/source
node packages/pi-runtime/jev-playground/cli.mjs score instance --out .tmp/arena/source --run-path /absolute/path/to/run
```

Proposal fields: `files` (path → text), `targetFile`, `targetSymbol`, unique `from`/`to`
mutation span, ordinary `task`, `grammar`, `seed`, and optional generator model/provider.
All mutation writes go to a new isolated destination. `mutatedSource()` is also an
importable author API. It adds no kernel rule. For synthetic generation use
`synthetic()` and `generate()`; `freeze()` is an explicit exported operation. Existing
challenge destinations are rejected. Hybrid may author richer files/tests/proposals
before invoking admission; no Codex callback is installed in the solve path.

## Campaigns and measurements

Implemented campaigns: recovery, verification-traps, branching-scale (4/8/16/32),
localization-scale (2/4/8/16/32/64), symbol-scale (2/4/8/16/32), grammar-boundary
(J0/J1/J2/J3), paraphrase-stability, generation-boundary, unsupported,
navigation-composition and multi-edit. The direct generator supports branching through
64. Operator, same-type variable, callable and required-argument faults are available.
Campaign metadata retains requested parameters; new specs record measured target-site
legal branching and whether admission actually found a broad-check trap.

Read-only composition is fixed `Symbol → ContainingFile → Tests`: Jev selects the
symbol, then deterministic existing-source relations return its file and tests.
There is no free-form planner. Baselines retain their existing classification and
navigation limitations; the scorer exposes those rather than correcting them.
`nextDifficulty()` suggests a content-free curriculum step from difficulty/failure
class only. It never reads an oracle or updates Jev policy/prompts. No Sol or hybrid
fallback arm is installed.

Scores distinguish task classification, candidate recall, region/file/symbol selection,
action generation, narrowing, action selection, exact verification, recovery,
premature/correct NeedsGeneration, correct Unsupported, relation selection, budgets
and provider failure. Unobserved stages use null where appropriate. Retained retrieval
sets and actual legal frontiers are recorded separately. Every Choice retains its
full distribution; edit choices additionally record whether enacted and whether the
single edit passes the admission oracle. This is not calibrated probability.

Times are separated into workspace generation, deterministic admission, Jev inference,
other deterministic solving and verification. Template generation makes no provider
calls; Codex implementation/authoring chat cost is not included. Provider usage reports
tokens and latency, but billed cost is unavailable. Reports are `report.md` and
`report.json`; raw receipts remain under `runs/`.
