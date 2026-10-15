# Jev task shapes and actual current-source repair

## What changed

The existing finite kernel remains in place. `TaskKind = Locate | Inspect | Repair | Verify | Unsupported` is a bounded Jev Choice over arbitrary task text and deterministic repository facts. A second head selects a finite inspection relation (file/config, symbol, tests, references). There is no generated plan, shell command, filename or answer paragraph.

- **Locate:** enumerate real objects → deterministic compression → Jev selects an ID or unknown → resolve table entry → host formats absolute path.
- **Inspect:** select existing file/symbol IDs; return bounded definitions or exact textual test/reference/config facts. These are not an LSP semantic call graph.
- **Repair:** only now reproduce, localize, inspect, enumerate/type-filter J2/J3 edits, apply, check, recover, finish.
- **Verify:** execute enumerated existing checks; cannot mutate.
- **Unsupported / NotFound / NeedsGeneration / Exhausted:** distinct explicit boundaries, not invitations to generation.

Navigation includes `.nix`, `.toml`, `.json`, `.md`, `.yaml`, `.yml`, `.conf`, `.patch` and JS/TS objects, capped at 2048 objects, depth seven, 48KB/object. Symlinks, hidden files, credentials, `.env`, vendor/build/node_modules trees remain excluded. Generic path/source-token relevance compresses this to 24 candidates. No Alacritty-specific branch exists. Repair remains limited to 64 JS/TS files and eight Node check targets.

Normal display uses `formatReceipt`: task kind, outcome, path or selected edit, exact check status, and compact counts. Full distributions/trajectory remain accessible through `/jev-receipt` or `--jev-receipt`. Existing SemanticTrace candidate/policy/action/mutation/verification lifecycles remain; no free-text terminal-IPC labels were introduced. Task kind is explicit in receipts and normal output.

## Dependency bug fixed

A temporary/source-only checkout need not have `node_modules`. The check subprocess now supplies only a small existing environment plus `PI_AGENT_MODE=jev` and NODE_PATH derived from the pinned runtime's TypeScript location. `semantic-check.mjs` resolves non-relative compiler imports from those same immutable modules; relative imports still resolve against actual checked source. Fixture SDK imports use the pinned ESM entrypoint. Test/compiler temp directories link the actual dependency root, not an assumed checkout node_modules path. No global npm install or replacement implementation is used.

Type-filtered edits likewise resolve pinned external types and Node declarations. Repeated candidates reuse immutable declaration ASTs and the previous Program. Operator descriptions include the actual existing expression, generically—not a repair-specific hint.

`tasks.test.mjs` copies the real current runtime source **without checkout node_modules**, and calls `RepositoryWorld.verify` against its actual semantic-control assertions. This passes; a missing-TypeScript loader failure is no longer mistaken for reproduction of the coding bug.

## Exact acceptance procedure

Reproducer: `packages/pi-runtime/jev-agent/self-repair.mjs`. Run with pinned dependencies available, e.g. from the built package:

```sh
node /nix/store/nvsdkm57wgv7dpn80zk589ikn7kd8ip1-pi-runtime-1.0.4/lib/pi-runtime/jev-agent/self-repair.mjs \
  --source=/home/becker/nixos-from-scratch/packages/pi-runtime \
  --repository=/home/becker/nixos-from-scratch \
  --output=/tmp/pi-real-comparison.json
```

The driver hashes/copies 27 current source/test/context files, excluding itself (setup instructions must not become policy evidence), into separate disposable workspaces. The running conductor is the healthy current kernel; repaired source is not hot-loaded into the conductor. Each session uses the actual extension, executes `/mode jev`, then submits the ordinary task. The SDK's generative model is registered but its streaming entrypoints are guarded. No generative provider or Fabric worker is dispatched.

Setup changes exactly one existing operator in `semantic-policy.ts`, function `shape`:

```diff
- margin:(sorted[0]?.[1]??0)-(sorted[1]?.[1]??0)
+ margin:(sorted[0]?.[1]??0)+(sorted[1]?.[1]??0)
```

This makes an existing semantic-control assertion observe margin 0.9 instead of 0.5. Setup confirms the **real** test fails by assertion, not loader failure. It separately records generic J2 enumeration, without passing its selected file/symbol or desired patch into the policy. Every policy receives only:

> Fix the failing semantic-policy behavior and verify the change.

There are no fixture-specific generator/controller/heuristic exceptions, target overrides, scripted repairs or supplied patch text. `baselineChoice` is unchanged. All policies receive the same source, grammar J2, test targets and defaults: 24 iterations, 32 evaluations, 120s, six transforms, ten check batches, two repeated states. Random uses deterministic seed offsets 0, 7, 19; this is a small sanity sample, not a statistical trial.

Main target SHA-256 before and after:
`cf1828407b0cfc3940bc3cf0116cb14175b7ed0fbf0d6a7bdbc1ba0b1e121b5e`.
The main checkout was never faulted. The successful temporary target returns exactly to the original hash. Full manifests, file/symbol tables, generated edits, trajectories, checks and probability distributions: `packages/pi-runtime/jev-current-source-results.json`.

## Final recorded results

| Task / policy | Outcome | Iterations | Transforms / reverts | Check batches | Wall time | Jev calls / heads |
|---|---|---:|---:|---:|---:|---:|
| Actual Alacritty Locate / Jev | Success | 1 | 0 / 0 | 0 | 0.462s | 2 / 3 |
| Current-source repair / Jev | Success | 5 | 1 / 0 | 3 | 12.196s | 8 / 59 |
| Same repair / random 0 | Exhausted | 20 | 6 / 6 | 6 | 47.365s | 0 / 0 |
| Same repair / random 7 | Exhausted | 22 | 6 / 6 | 6 | 25.834s | 0 / 0 |
| Same repair / random 19 | Exhausted | 22 | 6 / 6 | 6 | 25.839s | 0 / 0 |
| Same repair / unchanged heuristic | Exhausted | 21 | 6 / 6 | 6 | 29.148s | 0 / 0 |

**Every row: Codex calls 0; Fabric generative worker calls 0.** Baselines intentionally make no Jev calls. Recorded Jev totals for this final comparison: 10 evaluations, 62 heads, 25,886 input tokens, 2,125 output tokens, 1.706s reported inference latency. Billed cost is unavailable (`null`); these numbers are not total development cost.

The actual navigation request was:

> find me what file i would use to configure alacritty and produce its full path

It selected an existing object from 125 discovered objects / 24 presented candidates and returned:

```text
/home/becker/nixos-from-scratch/config/alacritty/alacritty.toml
```

Zero checks, transforms or mutations occurred. A fresh installed production `pi --agent-mode jev --no-session -p …` independently produced concise Locate output for the same request.

## Repair trajectory and uncertainty

1. Classify Repair: probability 0.99.
2. Select root source region: probability 0.98.
3. Inspect `semantic-policy.ts`. **File Choice was uncertain**: top 0.48 versus runner-up 0.19, below the 0.55 mutation/action admission threshold. The controller used its existing safe deterministic viewer fallback on the top repository-ranked file. This is not evidence that Jev alone confidently localized the file.
4. Select existing symbol `shape`: probability 0.83.
5. Generic J2 produced nine type-valid edits: three alternatives on each of `1-answer.noul`, comparator `b[1]-a[1]`, and the faulty margin expression. A batched relevance pass retained eight for Choice. Selected edit `E42c38adbedcb`: margin `+ → -`, probability 0.82. Other margin alternatives had 0.03 (`*`) and 0.04 (`/`); unknown 0.02. No replacement text was generated.
6. Exact affected check passes, then adjacent checks pass. StopSuccess probability 0.94. No revert needed.

The nine complete edit records and all Choice/Noul heads—not just the winning probabilities—are retained in the artifact. Its file table is the full repair universe; its symbol table covers the actual selected target; trajectories name every inspected file/symbol. Metrics count five completed iterations while trajectory includes six selected actions (the terminal selection returns before another iteration increment).

Actual verification history:

- `semantic-control.test.mjs`: fails before repair, passes after repair;
- `semantic-trace.test.mjs`: passes;
- `jev-agent/fixtures.test.mjs`: passes (deterministic J2/J3 ladder, generation guards);
- `jev-agent/tasks.test.mjs`: passes (routing, navigation, dependency and region regressions).

The three successful repair check batches are reproduction, affected target, then adjacent targets. Tests are not replaced with stubs.

## Baseline outcomes and an exposed kernel defect

An earlier comparison exposed premature global NeedsGeneration when a selected repository region contained no remaining legal move. This was a **kernel localization defect**, not useful evidence of Jev superiority. `advanceRegion` now retires exhausted regions and makes unvisited regions legal. All policies were rerun with this identical generic correction; the earlier rows are not used in the final table.

After correction, random 0 inspected `semantic-controller.ts` (`input`, `validResponse`) and exhausted its six transforms on unrelated comparison/variable repairs. Random 7/19 moved past `skill/policy.ts` into `jev-agent/tasks.ts` (`formatReceipt`, `selected`), then tried unrelated threshold operators. The heuristic moved past the same skill region into `jev-agent/actions.ts`, `navigationCandidates`, trying comparator/variable changes. All candidate checks failed the still-broken margin assertion, and all experimental edits were restored. Seeds 7 and 19 produced identical trajectories; they are not independent evidence.

Budget termination restores a pending unverified edit rather than claiming success. Consequently each exhausted row has initial reproduction plus five failed candidate check batches; its sixth applied candidate is discarded at the transform budget without another check. Six reverts include this terminal restoration, while actionFamilies records five explicit Revert actions. These are not six independently verified repairs.

## Final installed-classifier follow-up

The comparative table above refers to its archived 27-file manifest. A subsequent production Inspect probe asked for a named function **and** its containing path. The relation head initially treated this as File and returned only a path. The final finite criteria now explicitly cover named functions/symbols and their containing files; an uncertain Inspect relation is Unknown/NotFound rather than silently downgraded to File. No function-name-specific rule was added.

The final package `/nix/store/8rgl3kxqcnp6qs0zchmkf6bw3y7fh1rg-pi-runtime-1.0.4` passed the complete package checks and the previously failing fresh production probe:

```text
Jev · Inspect · Success
/home/becker/nixos-from-scratch/packages/pi-runtime/semantic-policy.ts
shape
3 Jev evaluations · 0 mutations · 0 Codex calls · 0 workers
```

A fresh production Verify request also passed all four actual check targets, with one Jev evaluation, zero mutations and zero generative calls. Repair behavior and baseline ranking were unchanged by the relation wording, but the real-source repair was independently rerun through `/mode jev` on the final installed classifier: Success, one `+ → -` edit, zero reverts, all affected/adjacent checks passing; 8 evaluations / 59 heads, 21,326 input / 1,786 output tokens, 1.293s inference, 12.372s wall time, zero Codex/workers. Its separate exact manifest and full receipts are `packages/pi-runtime/jev-final-validation-results.json`; these follow-up costs are not included in the comparative table's totals.

## Interpretation and limitations

Jev completed this real-source, existing-test, multi-file-context repair; the supplied random and unchanged heuristic policies did not within equal budgets. The strongest evidence is correct region/symbol/edit selection and fewer wasted mutations—not universal autonomous coding superiority. Deterministic filename/content compression and a safe viewer fallback did part of localization. The heuristic is weak, and one deliberately seeded arithmetic defect is not a representative repository benchmark.

Locate/Inspect are useful non-generative tasks, no longer routed through reproduction. Unsupported novel logic remains a NeedsGeneration boundary. References/tests/config facts are bounded textual relationships, not complete program semantics. Verify executes enumerated checks, not arbitrary user-provided commands. Discovery truncation and synchronous compiler macro time remain bounded-resource limitations; wall budgets are checked between macros, not OS-level CPU preemption.

This remains a trusted-repository experiment, **not an adversarial sandbox**. Test subprocesses can read HOME, fork or use network; the zero-generation guarantee covers the Pi/Fabric host dispatch/kernel, not arbitrary malicious test programs. Hybrid acceptance was not rerun here. No kernel/input pins or system closure changed; Factory missions, Droid management, Codex npm management and the credential launcher were preserved. The final tested package is installed at priority 2; all earlier Pi package fallbacks remain.
