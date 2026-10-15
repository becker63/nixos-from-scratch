# Read-only BuildBuddy history MCP

The existing Reader credential was verified against the official native
`BuildBuddyService.SearchInvocation` and `GetInvocationStat` APIs. No new
BuildBuddy key or plan entitlement is needed in this deployment. These are the
native protobuf RPCs, distinct from the public `/api/v1/GetInvocation` selector
API. The official generated browser client uses
`/rpc/BuildBuddyService/<method>`; the official protolet supports protobuf JSON.
Authentication is the runtime `x-buildbuddy-api-key` header.

Official schema snapshot: `1152ba9d7979edbe60aa17aaeba295f9e5578e9d`.
No generated client or source is downloaded at runtime.

## Integration

New package: [packages/buildbuddy-history](../packages/buildbuddy-history).
It provides `buildbuddy-history` (stdio MCP and export CLI),
`buildbuddy-history-analyze`, `buildbuddy-history-evidence`, and
`buildbuddy-history-tunnel`. It uses pinned nixpkgs Python/MCP/httpx dependencies,
plus pandas, PyArrow, NumPy, SciPy, and Matplotlib for deterministic analysis.
The existing `tunnel-client` 0.0.16 derivation is reused unchanged. No input pins
or system closures were changed or built.

Home Manager declares the package, `buildbuddy-history-tunnel.service`, and the
independent health service/timer. Existing BuildBuddy and Jev tunnels are
unchanged. The new units are Nix-built and installed separately; they skip
startup until their own tunnel ID is configured. Package and unit GC roots
preserve this installation without activating a system or Home Manager closure.

The MCP reads the existing owner-private
`~/.config/tunnel-client/buildbuddy-secrets/buildbuddy-bearer-header` only at
runtime. The tunnel references the existing OpenAI runtime key by file path.
No key is copied into source, arguments, derivations, responses, or a new secret
file. Provider errors are reduced to status and RPC code; credential-reflecting
responses are rejected. Logs are fetched only for a bounded evidence sample and
sanitized before excerpts are persisted.

## ChatGPT connection

Tunnel **buildbuddy-history** is configured and active:
`tunnel_6ac6b2303d4c81919894b9efd15f4f5d`.
The Nix-built `buildbuddy-history-tunnel.service` and health timer are enabled.
The client reports ready, successful control-plane polling, and a healthy stdio
`main` channel. Exactly one client owns this tunnel. Existing BuildBuddy and
Jev services remain healthy with their original processes.

No new API key is needed. The remaining account action is adding this tunnel
as a ChatGPT plugin. The tunnel is associated with the same organization and
ChatGPT workspace as the existing integrations.

```bash
buildbuddy-history-tunnel doctor
buildbuddy-history-tunnel health
systemctl --user status buildbuddy-history-tunnel.service
```

In ChatGPT **Plugins → + → Add custom MCP server**, choose:

- Name: **BuildBuddy History**
- Description: **Read-only historical invocation search, aggregation, and bounded metadata export**
- Connection: **Tunnel**, selecting `buildbuddy-history` or pasting
  `tunnel_6ac6b2303d4c81919894b9efd15f4f5d`.
- Authentication: **No authentication**. Provider authentication is injected
  locally; tunnel transport uses the existing OpenAI runtime principal.

Enable **BuildBuddy History**, **BuildBuddy**, and **Jev** together. ChatGPT can
search IDs with the companion, fetch exact logs/targets with official BuildBuddy,
and submit compact ambiguous evidence to the existing Jev tools.

## Tools

- `search_invocations`: `{filters?, page_size?:100, page_token?:"", direction?:"oldest"}`.
  `page_size` is 1–200. Filters: created/updated after/before, statuses,
  repository, command, user, pattern. Time bounds are timezone-qualified ISO-8601,
  lower inclusive and upper exclusive. Filters are ANDed; statuses are ORed.
  Pattern is an exact provider match. Tokens stay opaque and require the same
  query/order. Unknown statuses are retained when searching all statuses; the
  provider ignores an UNKNOWN status predicate, so the tool does not offer one.
- `invocation_stats`: `{grouping?:"date", filters?, limit?:1000}`.
  Provider groupings: date, repository, user, host, group, commit, branch,
  pattern. Limit 1–1000; potentially truncated aggregation lists are flagged.
  Dates use the provider updated timestamp and America/New_York timezone.
  Original counters, including the provider's `totalNumSucessfulBuilds` typo,
  are preserved. This deployment's aggregate omits disconnected builds.
- `export_invocation_history`: `{filters?, max_pages?:200, page_size?:100, verify_reverse?:true}`.
  At most 20,000 requested records and 200 pages. Metadata only, no bulk logs.
  All queries are rate-limited to one per second per client, including retries.
  Connect/read timeouts and at most three transient retries bound requests.
  Export upper creation time is frozen. IDs are deduplicated; output is ordered
  by creation timestamp and ID. A private lock prevents concurrent exports.
  Forward/reverse ID sets, page audits, native completed totals, and a separate
  unfinished-status search establish current accessible coverage.

Invocation JSON includes IDs, microsecond/ISO timestamps, completion status,
success or null for incomplete/unknown outcomes, termination detail when the
exit code identifies interruption/cancellation, original Bazel exit code,
duration, command, patterns, repository/commit/branch metadata, action count,
cache metrics, and allowlisted original metadata. The `completed_at` value is
explicitly labeled as last update for complete builds: exact BuildFinished time
is not supplied by SearchInvocation. Abbreviated provider patterns such as
`and 6 more` cannot reconstruct the full target set.

Search and native statistics were exercised through a real local stdio MCP
session with clean stderr. Tool schemas and real example outputs are included
with the analysis artifacts below. Large exports return a small manifest/path
summary instead of thousands of records; use the export CLI for long extractions
and paginated MCP search during ChatGPT conversations.

## Verified artifacts

All data and analysis are outside source trees:

`/home/becker/.local/state/buildbuddy-history/export-20261007T204508Z-24f02fb9/`

- `invocations.parquet`: **2,661** accessible records.
- `manifest.json`: two 27-page traversals, equal ID sets, no duplicates or
  timestamp-order violations; complete totals reconciled with native statistics,
  all **34 disconnected IDs** checked with a separate status-filtered search.
- **2,627 complete**: **1,795 success / 832 failure = 68.33%**.
- Creation range: **2026-09-24 through 2026-10-07**. Original 2,601 completed
  count grew by 26 (18 passes, 8 failures). Disconnected outcomes are retained
  and excluded from the completed-outcome denominator.
- `analysis.md`, `diagnostics.json`, daily/weekly/stratified rate CSVs, rolling
  and cumulative CSVs, session sensitivity tables (10/20/30/60/120 minute gaps),
  transition/streak distributions, and same-pattern/command repair proxies.
- `rolling-rates.png`, `cumulative-rate.png`, `session-rates.png`,
  `daily-rates.png`.
- `failure-taxonomy.md/json`, `failure-evidence.json`, and
  `jev-classification-native-responses.json`: **36 failures and 12 success
  controls**, stratified by date, target namespace proxy, command, outcome, and
  duration. 22 failures were handled by deterministic evidence/exit rules;
  14 ambiguous failures used the existing native `jev-1.13.0` MCP, totaling
  21,398 input / 1,805 output tokens. Full probabilities/legends/usage remain
  intact. Counts are illustrative sample counts, not population prevalence.
- `tool-input-schemas.json`, `mcp-example-search.json`, `mcp-example-stats.json`.

The export verifies currently readable retained records under the frozen upper
creation bound. It cannot recover deleted/expired/private invocations, and the
API does not supply a transactional snapshot of in-flight outcomes. No returned
invocation has a repository URL, so repository grouping cannot establish
project membership. Target paths provide explicit experiment-family proxies;
these are not verified mission IDs. Local session gaps are also proxies.

## Main statistical findings

The cumulative aggregate is near the original 68.3%, but local observed
performance varies substantially:

| Window | Minimum | Maximum |
|---|---:|---:|
| 50 invocations | 26% | 98% |
| 100 | 37% | 93% |
| 200 | 51.5% | 85% |
| 500 | 57.4% | 77% |

The 30-minute-gap session transition probabilities are **48.5% pass after
failure**, versus **78.1% after success**. Lag-1 correlation is 0.296. There are
331 within-session same-pattern/command/repository failed-to-passed pairs with
median elapsed time 60.2 seconds; broad target patterns make these repair
*proxies*, not verified agent repairs. The longest failure streak is 26,
compared with 5–9 in the IID fitted Bernoulli simulation reference and 8–14
in the homogeneous first-order Markov reference. Those fitted simulations are
diagnostics, not independent causal or significance tests.

Chronological held-out log loss (lower better): Bernoulli **0.6634**, Markov
**0.6313**, workload-stratified **0.6287**, session beta-binomial **0.6402**.
Paired session bootstrap intervals are in diagnostics: workload and session
models improve over the baseline in this held-out sample; the Markov interval
includes zero despite its better point score. Models use only prior outcomes
and training data. Duration/cache association tables are descriptive because
these measurements are produced during or after the build.

Workloads differ: build 63.6%, test 66.9%, run 93.0%, aquery 98.6%; target scope
all-targets 87.4%, experiments 65.9%, native 27.9% (with counts in CSVs).
Action-cache ratio >75% accompanies 82.0% success, versus 55.3% in the 50–75%
band; this does not identify the causal effect of cache reuse.

The strongest one-split diagnostic occurs around October 2, but its
session-block permutation p-value is **0.324**. Thus this analysis does not claim
a permanent change point or establish nonstationarity from that split alone.
The session-cluster bootstrap overall interval is 63.65–72.25%, conditional on
exchangeable-session assumptions; no independent-invocation interval is used.

**The apparent 68% plateau is a cumulative-average phenomenon. The chronology
supports workload differences, clustered outcomes, and short repeated
failure-to-success iterations as measurable process correlates. It does not
support treating every invocation as an independent trial with a constant local
68% probability, or claiming a universal mission-level law. Causation remains
unidentified.**

## Validation

12 tests passed in the targeted Nix build, covering protobuf default status
semantics, native filter mapping, pagination/deduplication/order, reverse checks,
unfinished reconciliation, partial export coverage, credential-safe failures,
RPC mutation rejection, MCP protocol/discovery, numerical pipeline outputs,
session calculations, deterministic taxonomy, and excerpt redaction.
Nix host service evaluation and systemd unit verification passed. Real Reader
search/statistics probes and local stdio MCP calls passed. Secret isolation and
existing service health are checked independently. ARM64 was built; AMD64
is declared but not built in this session.

## Sources

- [Official invocation protobuf](https://github.com/buildbuddy-io/buildbuddy/blob/1152ba9d7979edbe60aa17aaeba295f9e5578e9d/proto/invocation.proto)
- [Generated browser RPC client](https://github.com/buildbuddy-io/buildbuddy/blob/1152ba9d7979edbe60aa17aaeba295f9e5578e9d/app/service/rpc_service.ts)
- [Protobuf JSON transport](https://github.com/buildbuddy-io/buildbuddy/blob/1152ba9d7979edbe60aa17aaeba295f9e5578e9d/server/http/protolet/protolet.go)
- [Search authorization](https://github.com/buildbuddy-io/buildbuddy/blob/1152ba9d7979edbe60aa17aaeba295f9e5578e9d/server/capabilities_filter/capabilities_filter.go)
- [Status semantics](https://github.com/buildbuddy-io/buildbuddy/blob/1152ba9d7979edbe60aa17aaeba295f9e5578e9d/proto/invocation_status.proto)
- [Official Enterprise API documentation](https://www.buildbuddy.io/docs/enterprise-api/)

- [Official Secure MCP Tunnel setup](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)
