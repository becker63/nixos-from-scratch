# Attune research workbench

This directory contains two small frontends over one JSONL event contract. The
frontends are observers; scientific results remain in the experiment's own
artifacts. `events.jsonl` is a deterministic eight-row fixture shared by both.

## Run

```sh
nix develop -c research-textual
nix develop -c research-ratatui
nix develop -c codex app-server --stdio
nix develop -c research-textual --resume THREAD_ID
nix develop -c research-ratatui --resume THREAD_ID
```

Use `nix develop -c research-textual --check-fixture` and
`nix develop -c research-ratatui --check-fixture` for noninteractive fixture
smoke checks. Both frontends start `codex app-server --stdio` only after the
first prompt. Install Codex CLI through the existing npm-managed
`~/.npm-global` setup; the child process inherits the regular `~/.codex`
configuration and ChatGPT subscription login. No credential path or token is
passed through Nix.

Textual plots each treatment's best objective as a line and shows the prompt
and streamed assistant deltas. Ratatui plots the J0 objective curve, shows
evaluation latency as a sparkline, and displays the latest recall, harm, cost,
latency, and state. Both currently load the same static fixture at startup.

App Server server-side approval requests are declined by default. The clients
do not change the account's model, sandbox, or approval settings. Each selects
the account's default model from `model/list`; if no default is marked, it
uses the first model returned. Turn events are consumed from the JSON-RPC
stream. Press Ctrl+C to interrupt the active turn and Escape to stop a client;
it closes the child process. Pass `--resume THREAD_ID` to continue a saved
Codex thread.

## Event format

Each line is an `attune.research-event.v1` JSON object with experiment/run and
candidate IDs, parent candidates, treatment, iteration, timestamp, objective
and best objective, recall@10, harm, cost, latency, and state. Append one event
per candidate evaluation. Useful next views include treatment comparisons,
parent-edge frontier graphs, throughput and cost summaries, and run-state
filters. A future experiment writer should emit this format alongside its
reproducible raw results rather than relying on UI state.

## Test

```sh
nix develop -c python -m unittest discover -s packages/research-workbench/python/tests
nix build .#research-ratatui
```
