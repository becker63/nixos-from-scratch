# Codex visualization workbench

Textual is the default interactive Codex frontend in the configured xonsh
profile. It starts the official `codex app-server --stdio` child process on the
first prompt and inherits Codex's existing `~/.codex` account, settings,
sandbox, approval, model catalog, thread store, and project instructions.
Nothing in the Nix store contains a credential. `codex exec`, `codex app-server`,
login commands, and other native subcommands still go to the npm-managed CLI.
Use `codex-native` or `CODEX_VISUAL=0 codex` for the original Codex TUI. The
default changes after a Home Manager activation; this repository does not
switch the running system.

## Launch

```sh
codex                         # Textual, interactive; default model from account
codex --model MODEL_ID        # choose a model returned by model/list
codex --cd /path/to/project   # preserve project working directory
codex resume THREAD_ID        # resume an App Server thread
codex-native                  # original Codex CLI/TUI
CODEX_VISUAL=0 codex          # temporary native fallback
nix develop -c research-textual
nix run .#research-ratatui
```

`nix run .#research-textual` and `nix run .#research-ratatui` are also
available. Ratatui is an alternative frontend; it reads the same event and
visualization fixtures. Both clients start App Server only when a prompt is
sent. Escape closes the frontend; Ctrl+C interrupts the current turn.

Textual controls: Ctrl+G toggles graphs, Ctrl+N cycles graphs. Prompt commands
include `/next`, `/pin`, `/data`, `/table`, `/provenance`, `/graphs`,
`/jev on|off`, `/mode automatic|minimal|manual`, and `/fixture-study`.
Automatic mode is the default. The conversation remains active when JEv is
disabled or unavailable. Approval requests are declined by default; the
visualization tool itself performs no approval-gated operation. Codex execution
approvals are shown with their request details and wait for an explicit
`/approve ID` or `/deny ID` (Ratatui uses `:approve ID` and `:deny ID`). The
frontend will not accept unrecognized permission grant types.

## Visualization paths

`visualizations.jsonl` is a shared `attune.visualization.v1` fixture consumed by
both frontends. It records chart ID/type, labels and units, series or graph data,
identifiers, provenance, observed/inferred status, optional uncertainty, and
replace/update behavior. Payloads are bounded and validated. Explicit graph
edges must reference supplied node IDs. The fixture is separate from source
experiment measurements.

The deterministic router turns structured `attune.research-event.v1` rows into
a multi-treatment best-objective line chart, without inference. It reads
structured MCP results and bounded command output deltas, extracting only
complete JSONL records carrying that explicit research schema. The Codex dynamic `visualize` tool
accepts a bounded JSON specification and updates an existing chart by stable
ID. Codex protocol calls are supported by the installed 0.162.0
`item/tool/call` method; this adds no MCP service or listener.

JEv is an optional semantic observer using the existing OpenRouter Decisions
MCP and pinned `typesafe/jev-1.13` decision model. When the frontend starts in a
directory with an owner-private, non-symlink `.env`, it reads only
`OPENROUTER_API_KEY` at runtime and passes it to the child MCP process. Set
`CODEX_JEV_ENV_FILE` to an alternate credential file. The key never appears in
the store, chart payload, or logs. Default budget is three decisions per
session (`CODEX_JEV_BUDGET`, capped at eight). Requests contain compact
structured evidence and independent typed questions for graphworthiness,
compatible visualization type, and bounded priority score. Duplicate evidence
is coalesced. An unavailable key, disabled route, timeout, or provider error
falls back to deterministic behavior. JEv scores are relative judgments, not
calibrated probabilities. Existing Factory credential launchers are unchanged.

The small evaluation fixture has twelve cases covering benchmark curves,
ambiguous metrics, explicit dependencies, branching search, build timelines,
plain text, incomplete data, duplicates, updates, and multiple plausible graph
types. Run `research-textual --evaluate-routing` or enter `/fixture-study`.
The included JEv labels are explicit fixture outputs, not live inference: they
make strategy deltas reproducible and are not statistical evidence of model
quality. A live JEv decision is separately smoke-tested when credentials and
network access are available.

## Event contract and extension

Each `events.jsonl` row is an `attune.research-event.v1` measurement with
experiment/run/candidate IDs, parent candidates, treatment, iteration,
timestamp, objective/best objective, recall@10, harm, cost, latency, and state.
The observation UI does not modify scientific measurements. Extend the
experiment producer to append raw records beside its independently reproducible
artifacts. Then add a deterministic extractor or a compact ambiguous candidate
for JEv to classify. JEv chooses among representations; it cannot invent
values, categories, or graph edges.

## Checks

```sh
nix develop -c python -m unittest discover -s packages/research-workbench/python/tests
nix develop -c research-textual --check-fixture
nix develop -c research-textual --evaluate-routing
nix build .#research-textual .#research-ratatui
nix run .#research-ratatui -- --check-fixture
nix run .#research-graph-app -- --check-fixture
```

## Inline graph app

`research-graph-app` is the MCP Apps companion for showing a chart inline in a
ChatGPT/Codex app conversation. It accepts the same `attune.visualization.v1`
JSON used by Textual and Ratatui, validates it, and returns a linked MCP Apps
widget. The widget renders line, sparkline, bar, scatter, histogram, heatmap,
and explicit-node tree charts; every view has a table fallback and visible
provenance. The terminal Textual client remains a separate frontend: a terminal
screen cannot be embedded as an inline app, so the companion widget uses a
small HTML/SVG view over the shared data contract.

The Home Manager configuration declares a separate
`research-visualizer-tunnel.service`, guarded by its own local profile. No
existing Jev or BuildBuddy tunnel is reused. After creating a dedicated Secure
MCP Tunnel in the OpenAI platform, configure it with the owner-private runtime
key prompt:

```sh
nix run .#research-graph-tunnel -- configure --tunnel-id tunnel_YOUR_ID
nix run .#research-graph-tunnel -- doctor
systemctl --user start research-visualizer-tunnel.service
```

The service definition and `research-graph-tunnel` Home Manager package become
available after the next Home Manager activation. The `nix run` setup command
works before that activation.

Then add a custom MCP app in ChatGPT app settings using the **Tunnel**
connection and select that tunnel. Enable the `show_graph` tool. The app tool
registration is managed in ChatGPT; the Nix configuration supplies the
reproducible local server and service. The existing ChatGPT/Codex login is not
used for tunnel auth: the dedicated runtime key stays in
`~/.config/tunnel-client/research-visualizer-secrets/` with mode `0600` and is
never put in the Nix store. The current conversation’s Apps tool list must be
refreshed after the custom app is connected.
