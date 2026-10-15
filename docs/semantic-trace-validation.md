# SemanticTrace validation receipts

Architecture and limits: [semantic-trace.md](semantic-trace.md).

```
Pi / Fabric / Jev
       ↓ bounded enums, ids, parents, statuses, counts
SemanticTrace + grid-owned execution positions
       ├─ four-lane geometry
       ├─ 256-bin activity/result minimap
       ├─ ownership wash / short Jev and settlement bursts
       └─ lane occupancy micro-meter
```

## Current revision: calm, symmetric edges

The terminal no longer draws Pi execution overlays. It retains line numbers
without a separator and the larger edge reservations, now equal on both sides.
The geometry tests cover font sizes, fixed/dynamic padding, leftover pixels and
narrow windows. The private X fixture checks equal edge padding using colored
first/last PTY cells and verifies that trace events do not draw in either edge.

Validated and installed on 2026-10-08:

```sh
nix build .#alacritty-semantic-check --no-link --print-out-paths --no-update-lock-file
# PASS: Rust tests and private-X geometry, quiet-edge, IPC and clipboard checks.
nix profile upgrade alacritty-semantic --no-update-lock-file
# Installed for new terminal windows; existing terminal processes stay running.
```

## Previous revision: separated semantic geometry

The user clarified that the **added instrumentation**, not transcript typography,
was too small and crowded. The temporary 14pt / 4px typography adjustment was
reverted in both repository and live configuration. Text remains 12pt with zero
font offset.

- Four execution tracks now have 1.5 font-cell spacing rather than fixed 5px
  spacing. Stroke width is at least 2px, nodes are larger, and Jev's five
  separated microbars stay inside their own track. Eleven left cells are
  reserved; the right history plane remains 8 physical pixels.
- Legacy rejection tokens no longer consume the main-agent scope or silently
  settle green. Repeated reasoning tokens update the existing generation scope.
- Anchor validation reuses its BTreeMap instead of allocating a vector per draw.
- The bridge fixture now validates scope identities, active parents and complete
  settlement; it additionally tests headless isolation, negative acknowledgements,
  unsafe window IDs and bounded queue overflow.

Exact validation commands/results:

```
nix build .#alacritty-semantic .#alacritty-semantic-check .#pi-runtime --out-link /tmp/pi-instrument-spaced --print-out-paths
# PASS: 274 Rust tests, private-X pixel/protocol/clipboard fixture, bridge test
nix build .#alacritty-semantic-check --out-link /tmp/pi-instrument-spacing-check --print-out-paths
# PASS: additional structural pixel assertion: four separated lane segments
NODE_PATH=/tmp/pi-trace-node-modules node packages/pi-runtime/semantic-trace.test.mjs
# PASS: 21 bounded messages, stateful lifecycle and fail-closed transport tests
nix build .#pi-runtime --out-link /tmp/pi-instrument-spaced-runtime --print-out-paths
# PASS: final package includes the additional transport tests
nix profile upgrade alacritty-semantic pi-runtime
nix profile upgrade pi-runtime
# PASS: targeted user profile only; original Alacritty fallback retained
node /tmp/pi-instrument-await-spaced.mjs
# PASS: final installed live Pi has 17 content-free lifecycle receipts
```

Final renderer: `/nix/store/7vkj4jq1llckp1di04jc83firc7q6xnl-alacritty-0.17.0`.
Final private-X check: `/nix/store/ns1dlyy4qg3n0q3sc4q3csz4bg9vk9z2-alacritty-copybuffer-check`.
Final Pi: `/nix/store/bp3siwbhxwgrkw6vpwfjh2frbf98ybhj-pi-runtime-1.0.4`.
Mutable Pi settings now reference the final runtime; credentials were untouched.

Inside a fresh rebuilt terminal, startup ran the installed bridge verification
inside a native Verify scope. The live model then exercised Codex → Fabric → Read
→ Jev (three questions/pass), shell/pass and shell/failure, and finished
`Native semantic smoke passed`. Receipt:
`~/.local/state/pi-semantic/spaced-live-receipt.jsonl`.

Pixel artifacts: `~/.local/state/pi-semantic/spaced-screenshots/`, including
`lattice.png`, `jev.png`, `passed.png`, `failed.png`, `reset.png`, `legacy-pass.png`
and `legacy-reject.png`. The last live window had closed before final screenshot
capture; fixture screenshots remain available. Original terminals were never killed.

A mistyped keyboard-injected slash command was **not** counted as acceptance.
The successful smoke used an exact initial Pi prompt, without keyboard injection.
Jev's completion advisory remained uncertain (0.78 completion / 0.67 verification
debt); tests, not that advisory, establish the passing checks above. The fixed
retention budget and deferred navigation/archival features remain limitations,
not completed capabilities.

No protected pins, Asahi/gaming configuration, system closures or Factory mission
processes were changed. `jj` is still a JSON utility here; Git provides the audit.

## Earlier passing commands

- `nix build .#alacritty-semantic .#alacritty-semantic-check .#pi-runtime --out-link /tmp/pi-instrument-handoff --print-out-paths`: PASS.
  - Alacritty: `/nix/store/1715d1ia76iwfaifmfk3n9gdy9h7bvwl-alacritty-0.17.0`.
  - Private-X check: `/nix/store/y2i4ljlqxnvwi8ihfp4gwgrg7lcmq0gm-alacritty-copybuffer-check`.
  - Pi: `/nix/store/c4f9kjms2iix41xdggvm4s7jgzkglwp1-pi-runtime-1.0.4`.
- Rust checks: 272 tests passed, including typed transitions, nesting/parallel lanes, retention budget, reflow, repaint and eviction. No tests disabled for this mission.
- Private-X fixture: PASS enum transitions, invalid kind/metric/parent/window/text rejection, lattice/map pixels, isolated Jev-versus-Codex geometry, pass/failure distinction, neutral reset, PTY repaint retention, full-scrollback copy/clear regression.
- `NODE_PATH=/tmp/pi-trace-node-modules node packages/pi-runtime/semantic-trace.test.mjs`: PASS strict TypeScript plus 21 private Unix-socket lifecycle messages and no prompt/state/answer leakage. Also runs during package installation.
- `nix profile install --priority 3 .#alacritty-semantic`, `nix profile upgrade pi-runtime`, then `nix profile upgrade alacritty-semantic`: PASS. Original Alacritty profile entry retained as fallback.
- Final compositor-owned fresh Pi window: PASS exact live Fabric program, 16 safe events: Codex, Fabric/pass, Jev count 3/pass, read/pass, shell/pass, shell/failure. Verified exported mode is `tui`; socket/window present.
- Production TraceTransport against real final socket: PASS parented Fabric/Jev start-finish acknowledgements, transport remained enabled.
- `/trace-check` inside rebuilt Pi: PASS installed bridge verification. `/trace-smoke` offers explicitly synthetic dense geometry.
- `git diff --check -- . ':!patches/*.patch'`: PASS. Standard unified-patch blank context lines retain required spaces.
- Actual Jujutsu `jj status` / `jj diff --stat`: cannot run because checkout has no `.jj` metadata. PATH's `jj` is a JSON utility. Git status/diff baseline used; no repo migration.
- `git diff --numstat -- flake.lock nodes/nixos-btw/configuration.nix modules/nixos/system/gaming.nix`: empty. No kernel/input pins, Asahi, gaming, system closures, or Factory processes changed.

## Inspected failures / corrections

Completion snapshot drift was fixed by generating the three completion artifacts, not disabling tests. An incomplete patch caused by tool-output truncation was regenerated directly on disk. Pixel inspection caught an opaque warning panel on rejected JSON; logging is now debug-only. Black background exposed a crop sampling only padding; structural crop was corrected. Live Pi repaint erased cell carriers; the bounded grid index now restores them before draw/reflow, with a real PTY repaint regression. One under-specified smoke produced malformed Jev arguments and failed closed; the exact `{state, questions}` payload passed. Initial smoke window reached its bounded shell deadline; final window is compositor-owned and stays open independently of Fabric tasks. Original terminals were never stopped.

## Artifacts / reproduction

`~/.local/state/pi-semantic/screenshots/`: neutral, lattice, Jev, pass, failure, reset.
`~/.local/state/pi-semantic/final-live.png`: actual final Pi window.
`~/.local/state/pi-semantic/final-live-receipt.jsonl`: content-free lifecycle receipt.

```
alacritty --class SemanticTrace -e pi --tui-mode regular
```

The class avoids the ordinary Alacritty compositor opacity rule without changing desktop configuration. Then `/trace-smoke` or `/trace-check`. No system switch required.

## Limits / deferred

Four lanes; overflow shares the final lane. Latest 2048 scopes / 4096 positions, not unlimited archival retention. Repaint preserves execution positions; explicit trace reset clears scopes. Per-frame work is bounded by these budgets, not 100k scrollback lines; rare reflow scans history cells. Conservative full semantic damage remains.

Real Jev exposes question count only; default uncertainty zero is reserved, not measured confidence. Detached worker launch is observed, later detached settlement is not scheduler-linked. No raw questions, results, prompts or credentials emitted.

Deferred: keyboard/click navigation, read-only trace mode, textual HUD, deeper OSC 133, coalesced archival history, aggregate Jev uncertainty/latency, scheduler-aware lanes, finer damage and cached projections.
