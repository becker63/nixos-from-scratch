# Native Jev MCP for ChatGPT

Implemented on 2026-10-07. `jev-tunnel.service` and
`jev-tunnel-health.timer` are Nix-built, installed in the user profile, enabled,
and now active. The user created the separate tunnel
`tunnel_6ac6a88dd93c8191b079ddb594419b5f` named **jev**.
BuildBuddy remains on `tunnel_6ac69d9d158481919c6f6d843197ccea`.

The initial profile contained an unsupported `control_plane.max_inflight` YAML
field. This was fixed by setting the supported `--control-plane.max-inflight 4`
CLI flag instead. A Nix install check now feeds the generated stdio profile to
the pinned client to catch schema incompatibilities before installation.
The real profile passes `doctor`; the live main stdio channel reports
`probe_status: ok`, and the client reports `control_plane_max_inflight: 4`.

## Tunnel creation and activation (already completed)

Create **jev** at
[Platform tunnel settings](https://platform.openai.com/settings/organization/tunnels),
attaching the same organization and ChatGPT workspace as BuildBuddy:

- Organization: `org-L1oHU90khgz2T52saXWgDLtx`
- ChatGPT workspace: `c5f8d126-679d-4052-8282-14e16dfdfafb`

Alternatively, with an OpenAI admin key permitted to manage tunnels, use the
installed pinned CLI. Enter that key with hidden terminal input; never place it
in arguments, this repository, or shell history:

```bash
read -r -s -p 'OpenAI admin key: ' OPENAI_ADMIN_KEY
export OPENAI_ADMIN_KEY
tunnel-client admin --json tunnels create \
  --name jev \
  --description 'Native TypeSafe Jev semantic decisions over local stdio MCP' \
  --organization-id org-L1oHU90khgz2T52saXWgDLtx \
  --workspace-id c5f8d126-679d-4052-8282-14e16dfdfafb
unset OPENAI_ADMIN_KEY
```

Use the returned **new** ID, allowing 30 seconds for tunnel propagation:

```bash
jev-tunnel configure --tunnel-id tunnel_REPLACE_WITH_NEW_JEV_ID
jev-tunnel doctor
systemctl --user start jev-tunnel.service jev-tunnel-health.timer
systemctl --user status jev-tunnel.service
jev-tunnel health
journalctl --user -u jev-tunnel.service -n 30
```

Configuration refuses the BuildBuddy tunnel ID. It references the existing
owner-private `~/.config/tunnel-client/buildbuddy-secrets/openai-runtime-key`;
it never copies its contents. If that runtime principal lacks Use permission
for the new tunnel, grant it that permission, or supply an existing private key
file using `jev-tunnel configure --tunnel-id ... --runtime-key-file /absolute/path`.
Run configuration once; its metadata is in `~/.config/tunnel-client/jev.json`.
The profile is generated on each startup using the Nix-pinned MCP executable.

In ChatGPT **Plugins → + → Add custom MCP server**, set:

- Name: **Jev**
- Description: **Bounded native TypeSafe choice, score, and noul judgments**
- Connection: **Tunnel**; select **jev**, or paste its new ID.
- Authentication: **No authentication**. The local protected launcher authenticates
  to TypeSafe; the tunnel authenticates to OpenAI.

Keep the service running during discovery. Confirm `jev_decide` and
`jev_decide_batch` appear, enable **Jev** alongside **BuildBuddy**, then call a
small typed judgment with compact evidence. Workspace permission to add custom
MCP servers and Platform Tunnels Read + Use are required. Tunnel readiness and `main` channel status are verified. Discovery **through
ChatGPT** still needs a connector in that workspace; local stdio discovery and inference were verified.

## Implementation

- [native.py](../packages/jev-mcp/src/jev_mcp/native.py): separate native FastMCP
  server, fixed `https://api.typesafe.ai/v1/systemone`, default `jev-1.13.0`.
- [native.nix](../packages/jev-mcp/native.nix): `jev-native-mcp`, reusing the existing
  `jev-mcp` Python/MCP/httpx packaging and dependencies from the frozen nixpkgs.
  Installs the existing [Fabric credential parser](../packages/pi-runtime/credential.py)
  without changing it or invoking its stdout credential command.
- [tunnel.nix](../packages/jev-mcp/tunnel.nix),
  [tunnel.py](../packages/jev-mcp/tunnel.py), and
  [services.nix](../packages/jev-mcp/services.nix): `jev-tunnel`, runtime profile
  preparation, per-tunnel singleton lock, restart supervision, and independent
  one-minute readiness/polling checks. Health failure restarts only Jev.
- [modules/home/packages.nix](../modules/home/packages.nix) declares the same
  services/timer and package for future Home Manager activation;
  [outputs/perSystem/packages.nix](../outputs/perSystem/packages.nix) exposes both
  new packages on ARM64 and AMD64. Only ARM64 was built here.
- Reuses **unchanged** `tunnel-client` **0.0.16** and its release hashes.
  Factory's compatibility server, launcher, and running Droid remain unchanged.

Targeted package build and narrow user-service installation require no system
closure or Home Manager activation:

```bash
nix build .#jev-tunnel --no-link --no-write-lock-file
nix profile add .#jev-tunnel --no-write-lock-file
jev-tunnel install
```

Services log to the user journal. Jev health URL is written to
`~/.config/tunnel-client/jev-health-url`; `/healthz`, `/readyz`, `/metrics`, and
`/ui` are loopback-only. MCP uses stdio, with no network listener.
The health timer requires readiness and a successful control-plane poll.
The daemon's admin UI supplies channel diagnostics after activation.
The singleton lock covers launches through `jev-tunnel`; use the managed service
instead of invoking a second raw `tunnel-client` for the same ID.

## Tools and limits

Exact discovery-produced JSON input schemas for both tools are in
[jev-native-mcp-input-schemas.json](jev-native-mcp-input-schemas.json).

`jev_decide` takes `{state, questions, model?}`. State is text, an object, or an
array. Questions are a named map. Each question has `type`, `instructions`, and
optional or required `criteria`:

- `choice`: 2–255 alternatives, map from name to description (text, structured
  JSON, or null). Include `unknown` for insufficient evidence.
- `score`: an ordered rubric of 2–10 descriptions.
- `noul`: binary probability; optional criteria describe both `true` and `false`.

Instructions can be text or structured JSON. The default model is pinned to
`jev-1.13.0`; callers can explicitly choose another native `jev-*` model.
Per-state size is 32KiB and per-request total is 64KiB, with 1–64 questions.
Byte limits are conservative application limits, not a token-budget guarantee.

`jev_decide_batch` takes `{records, model?, concurrency?}`. Each record is
`{id, state, questions}`. IDs must be unique. Limits: 1–32 records, 128 questions,
512KiB overall; concurrency 1–4, default 4. A process-wide semaphore also limits
concurrent tool calls to four native requests. Equal JSON states (object key
order ignored, arrays ordered) share a native request with namespaced question
IDs. A shared state must fit the 64-question/request limits; otherwise the whole
call is rejected **before inference**. Separate states generate separate
requests. Each call remains independent; there is no stochastic output cache.

Single results contain `response` (the entire native envelope) and `metrics`.
Batch results contain ordered per-record `results`, complete native `requests`,
aggregate `usage`, and latency/request/success metrics. `request_index` links
records to the shared envelope. Usage is counted once per successful native
request; failed/retried attempts may incur unreported usage. All native fields,
probabilities, legends, confidence, model identity, and any provider cost remain
intact. No cost is fabricated when the provider omits it.

Timeouts: 5-second connection, 15-second HTTP operations, 60-second total deadline
per native request. At most three attempts; retry only network failures or
408/429/500/502/503/504/529, exponential delays, with numeric Retry-After bounded
at five seconds. Retried inference can incur extra charges. Non-transient errors
are not retried. Provider error bodies are discarded because they may contain
credentials or input. Successful responses reflecting the credential are
rejected. Tool errors use fixed messages or numeric status only.

## BuildBuddy research example

Supply deterministic normalized evidence rather than complete logs:

```json
{
  "state": {
    "invocation_id": "example-only",
    "bazel_exit_code": 1,
    "error": "error: expected type u32, found []const u8",
    "preceding_invocation": null
  },
  "questions": {
    "failure_kind": {
      "type": "choice",
      "instructions": "Classify from evidence. Exact errors and exit codes take precedence. Abstain if insufficient.",
      "criteria": {
        "compiler": "Compiler or type-checking failure",
        "bazel_configuration": "Invalid Bazel configuration or target graph",
        "scientific_assertion": "Failed scientific assertion",
        "expected_negative": "Documented expected negative experiment",
        "dependency": "Dependency or acquisition failure",
        "infrastructure": "Infrastructure or remote-execution failure",
        "timeout": "Explicit timeout",
        "unknown": "Insufficient evidence or no supported category"
      }
    },
    "evidence_sufficient": {
      "type": "noul",
      "instructions": "Is the supplied log evidence sufficient to identify a cause?"
    },
    "current_change_related": {
      "type": "noul",
      "instructions": "Does supplied evidence support the current speculative change causing the failure? Missing change evidence must not be treated as proof."
    },
    "agent_repair": {
      "type": "noul",
      "instructions": "Does explicit supplied mission evidence support this being an agent repair iteration?"
    },
    "preceding_related": {
      "type": "noul",
      "instructions": "Do explicit shared errors or changes support relation to the preceding invocation? Missing preceding evidence is uncertainty."
    },
    "ambiguity": {
      "type": "score",
      "instructions": "How ambiguous is cause attribution from this evidence?",
      "criteria": ["Direct deterministic evidence", "Several plausible explanations", "Insufficient evidence"]
    }
  }
}
```

Let ChatGPT interpret uncertainty and calculate statistics. Use deterministic
code for exits, counts, and exact messages. The supplied historical totals are
2,601 invocations, 1,777 passed and 824 failed (~68%); they were not reacquired or
verified here. Jev does not expand BuildBuddy's current historical enumeration
capability, and semantic classification alone cannot explain a stable pass rate.

## Verification and live smoke

- Targeted Nix build: passed; **39 mocked/protocol/launcher/tunnel tests**.
- Host Home Manager service evaluation: passed for Jev and BuildBuddy.
- `systemd-analyze --user verify` of all three new units: passed.
- Local stdio: initialization, tool discovery, valid calls, invalid calls tested.
- Tests cover all three primitives, full probability/confidence/legend preservation,
  shared states, separate states, bounded concurrency/retries/deadline, stable IDs,
  partial failures, malformed response/input rejection, no caching, singleton lock,
  credential mapping and private permissions, and synthetic compiler classification.
- Live stdio inference used the actual protected launcher and existing JEV_KEY.
  Native returned `jev-1.13.0`, **464 input / 88 output tokens**, latency **191.4ms**,
  one attempt. Compiler probability 1.0 (unknown/infrastructure/assertion 0.0);
  sufficiency noul 0.85; ambiguity score 0.53 with probabilities
  `{ "0": 0.58, "1": 0.3, "2": 0.12 }` and confidence 0.19.
  Provider cost was absent. These are synthetic evidence judgments, not a research
  conclusion. The test was repeated once after the harness failed to decode the
  first successful text-only MCP response; no evaluation batch was launched.
- Live child stderr was empty. Credential scans of changed/generated artifacts,
  installed package outputs, and Jev service logs passed. `.env` remains ignored,
  owner-private (0600), and unmodified; its other secrets were preserved.
- Final BuildBuddy health and readiness checks returned 200; its original PID
  217457 and Factory Droid PID 3223 were preserved.

References: [native TypeSafe API](https://docs.typesafe.ai/api),
[versioned models](https://docs.typesafe.ai/models),
[official Secure MCP Tunnel setup](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels).
