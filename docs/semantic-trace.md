# SemanticTrace — native execution edges

The current terminal uses calm, symmetric edges. The follow-up
`patches/alacritty-calm-gutter.patch` stops drawing the execution lattice,
ownership washes, lane meter and right minimap, and cancels their animation timer.
It keeps quiet line numbers without a separator and reserves eleven font-scaled
cells on both sides of the text grid. Spare sub-cell pixels are split between the
edges; very narrow windows reduce both reservations equally.

The Pi settings no longer load the visual trace extension. Trace IPC, scope state
and grid anchors remain available to callers. The projection
design below describes the earlier visual implementation, retained in source but
no longer called by the display.

```
Pi message/tool lifecycle + Fabric host invocation observer
                    │ enum / id / parent / phase / status / count
                    ▼ exact-window acknowledged Unix IPC
              SemanticTrace (2048 retained scopes)
                    │ grid cell anchor ids (4096 indexed positions)
                    ├── four-lane geometric execution lattice
                    ├── 256-bin activity map + separate result ticks
                    ├── text-safe ownership wash + 700ms settlement
                    └── four tiny lane-occupancy segments above the PTY
```

## Renderer ownership

`patches/alacritty-semantic-trace.patch` applies after the existing copy-buffer
and gutter patches. It replaces the old display animation engine, while keeping
`gutter-event` as a compatibility adapter. New modules/contracts:

- `alacritty/src/semantic_trace.rs`: fixed kinds, phases, statuses, validated scopes,
  lane allocation, bounded history and rectangle projection.
- CLI / IPC / event / window context: `trace-event`, `trace-reset`, synchronous
  anchoring under the terminal lock, exact window targeting and acknowledgements.
- terminal `CellExtra`, `Grid` and resize: sparse marker metadata travels with cells
  during reflow. The bounded position index adjusts during regional scrolling,
  restores sparse marker carriers after PTY repaint, evicts positions outside
  retained history, and rebuilds only after resize. Execution positions survive
  character erasure; `trace-reset` clears instrumentation explicitly.
- display: eleven left cells reserved once, eight physical right pixels reserved;
  transcript text never contains trusted chrome. Existing copy-buffer survives.

The lattice is geometry, not Unicode art. Violet denotes generation/edit; cyan
Fabric/search/tool; blue read/shell/worker; cream verification; coral failure.
Result endpoints are green/coral. Execution tracks are spaced 1.5 font cells apart,
with strokes at least two physical pixels and larger hard-edged nodes. This scales
with display/font size instead of packing four lanes into 20 pixels. Jev has up to
five separated microbars contained inside its lane. PTY font size/row spacing remain
unchanged. The right map has separate activity and result
channels, plus a one-pixel viewport position indicator. Jev uses teal segmented
microbars, a short 700ms burst and a narrower persistent map segment. Counts affect
segment density logarithmically. These bars are **not posterior samples**.

Ownership washes are 1.2% alpha, at most one per lane (4.8% combined). No cards,
labels, model-authored strings, titles or prompt contents are accepted as chrome.
The top-edge lane meter uses fixed geometry only; a textual HUD is deferred.

## Protocol

```
alacritty msg trace-event --id 1 --kind codex --phase start --status active
alacritty msg trace-event --id 2 --parent 1 --kind jev --phase start --status active --count 24
alacritty msg trace-event --id 2 --parent 1 --kind jev --phase finish --status passed --count 24
alacritty msg trace-event --id 1 --kind codex --phase finish --status passed
alacritty msg trace-reset
```

All require `ALACRITTY_SOCKET` plus `ALACRITTY_WINDOW_ID`, or explicit socket/window
options. No broadcasts. Kinds: human, codex, fabric, jev, search, read, edit, tool,
test, verify, worker, shell-command. Start/update require active; finish requires
passed/failed/cancelled. An existing active parent is required. Id/kind/parent are
immutable and finished scopes cannot reopen. Count is u16. Optional uncertainty
is 0–1000 permille; the current real Jev bridge does **not** calculate uncertainty
and sends zero as a reserved/default value, not as a confidence claim.

Raw JSON envelope: `{"TraceEvent":{"event":{...bounded fields...},"window_id":42}}`.
Both structures reject unknown fields. `TraceReset` carries a window id only.

## Pi integration

`packages/pi-runtime/semantic-trace.ts` remains packaged but is no longer loaded
by `modules/home/pi.nix`. The optional bridge implements the lifecycle mapping
below. Pi uses `tuiMode = "regular"` so history belongs to the
terminal rather than Pi's fullscreen alternate-screen transcript.

- agent_start/end: enclosing human/control scope, sharing the shell base lane
  so Fabric retains two distinct child-worker lanes.
- assistant message_start/end: Codex generation scope, error/abort settlement.
- tool_execution_start/end: Fabric, search/read/edit/shell/tool scopes, nested
  parent correlation and actual `isError` settlement.
- `pi-fabric:semantic-v1`: host invocation start/end for Jev, workers, nested Pi
  operations and generic providers. Whitelisted refs map to enums, never text.
- `/trace-check`: actual installed bridge test inside a native verification scope.
- `/trace-smoke`: explicitly synthetic Codex/Fabric/read/Jev/verify/pass/failure
  demonstration; no provider requests and no credentials.
- shutdown: active scopes cancelled, bounded IPC queue flushed.

`semantic-fabric-patch.mjs` fail-loud patches the pinned Fabric distribution at
actual registry/execution observation hooks. Jev's question count is taken from
validated host arguments, before any preview truncation. No question labels,
state, answers, prompts, errors or credentials reach the event bus or terminal.
Headless workers do not own or reset the parent window's chrome. Transport is
serialized, with 256 messages and 800ms per-request timeout. Overload or an old
terminal disables observation instead of dropping unmatched lifecycle halves.

## Cost and retention

Per event: bounded scope lookup/validation, one sparse cell anchor and one IPC
message. Terminal scrolling adjusts at most 4096 indexed points; resize alone
scans history cells to recover reflowed positions. Erase/eviction invalidation
per frame is bounded by the anchor index, never by 100,000 history lines.
Projection is bounded by 2048 scopes × 256 map bins; only the last 128 scopes emit
lattice geometry, and ownership bands are capped to four. At most four active
lanes are distinct; additional concurrent scopes share the final lane.

The map spans the whole current scrollback coordinate range, but retains only
the latest 2048 scopes/4096 anchor positions. It is **not lossless archival trace
storage** for arbitrarily long sessions. Evicted positions are discarded. Character repaint does not delete the
execution history associated with a logical grid position; terminal reset replaces
the grid and `trace-reset` clears scope state. Alternate-screen anchors belong to that grid, not primary
history. Animations stop after 700ms; active idle scopes remain static. Currently
semantic draws mark full damage for partial-present correctness; finer damage
tracking and cached projections are future performance refinements.

## Validation and artifacts

Safe targeted builds only:

```
nix build .#alacritty-semantic .#alacritty-semantic-check .#pi-runtime
```

The package runs Alacritty's existing tests plus typed protocol/state and grid
scroll/reflow/repaint/eviction tests. `alacritty-semantic-check` extends the existing
private-Xvfb fixture: all enum transitions, parent/target rejection, arbitrary
JSON text rejection, lattice/map changes, Jev distinctness, pass/fail pixels,
neutral reset, PTY repaint retention, and full-scrollback clipboard regression. Its output contains
`screenshots/{neutral,lattice,jev,passed,failed,reset}.png` and `result`.
The Pi package runs the private Unix-socket bridge test during installation.

## Upstream investigation / deliberate deferrals

Reviewed Alacritty issue #5850 and open PR #8961, *Track OSC 133 Prompts and Clear
on Resize* (https://github.com/alacritty/alacritty/pull/8961). That work anchors a
current prompt cursor, clears it on OSC 133 C, and erases/redraws a live prompt
before reflow, excluding alt-grid. It depends on newer VTE Handler methods. It
is not a historical nested execution store. This mission retains Xonsh's existing
pre/post-command IPC and does not change prompt redraw semantics or dependency
pins. Cell-carried trace markers address retained history separately.

Deferred: deeper OSC 133 prompt/output distinction, semantic previous/next failure
navigation, minimap click hit-testing, read-only trace projection, textual HUD,
archival/coalesced history beyond the fixed budget, aggregate Jev uncertainty,
latency instrumentation and scheduler-aware lane allocation. `agents.run` spans
its actual blocking worker lifecycle; `agents.spawn` currently shows the launch
call only, not later detached settlement. No inferred test success from scraped
transcript or command text. Use `/trace-check` for explicit real verification.
