{ pkgs }:

let
  opencodeLongRunningCommandInstructions = pkgs.writeText "opencode-long-running-commands.md" ''
    # Long-running Commands

    When running local commands that may keep executing, stream logs, watch files, start servers, run dev loops, or otherwise take a long time, use opencode-pty instead of blocking the foreground shell.

    Prefer `pty_spawn` for detached local command sessions, inspect them with `pty_list` and `pty_read`, send input with `pty_write`, and stop them with `pty_kill`. Use titles that describe the session, and set `notifyOnExit` for long validations or builds.

    Use opencode-background-agents for delegated agent work, not for ordinary shell processes. Use AFT shell support for compressed short command output and as a fallback when PTY tools are unavailable.
  '';

  opencodeAftFirstInstructions = pkgs.writeText "opencode-aft-first.md" ''
    # AFT-first Repository Navigation

    Prefer AFT tools before raw file-reading when exploring unfamiliar, large, or noisy code.

    Use `aft_outline` before reading many files or asking what is in a repo, directory, module, or large file.
    Use `aft_zoom` to inspect a specific symbol, file region, or focused result after an outline identifies where to look.
    Use `aft_inspect` when you need structured facts about a file or module instead of dumping content.
    Use `aft_import` when tracing dependency, import, or module relationships.
    Use `aft_conflicts` before risky edits, after several overlapping edits, or when concurrent changes might collide.
    Use `aft_safety` before broad refactors, destructive edits, large patch sets, or changes with hidden risk.

    Use raw `read`, `grep`, `glob`, or shell search only when the target is already known and small, the query is a simple exact lookup, or AFT cannot answer with enough precision.

    Before reading more than two files for orientation, use `aft_outline`.
    Before running broad `rg` or `find` searches, consider whether `aft_outline`, `aft_import`, or `aft_inspect` would answer with less context.
    Before editing after a long exploration, consider `aft_conflicts`.

    For shell commands, keep using AFT-backed `bash` with compressed output. Avoid pasting large command output into the conversation; rely on AFT summaries and output paths unless the full output is necessary.
  '';

  opencodeFastEditInstructions = pkgs.writeText "opencode-fast-edit-policy.md" ''
    # Fast Edit Policy

    Optimize edits for throughput and auditability. Prefer fewer, larger, coherent write operations over many tiny patch calls.

    Edit planning:
    - Before editing, identify the exact files that need to change.
    - Use AFT and cheap routed context lookups for locating code before reading many files.
    - Use background agents for parallel read-only prep or risky sub-work that benefits from polling.
    - Keep the primary agent responsible for final synthesis and worktree audit.

    Write strategy:
    - For tiny localized changes, use the normal edit/patch path.
    - For generated artifacts, OpenSpec files, markdown plans, skills, config snippets, and new files, prefer full-file writes when that is clearer and faster than surgical patching.
    - For medium multi-file implementation, batch related edits into one coherent apply step when possible.
    - Avoid long sequences of mechanical patch calls. If the edit plan would require many small patches, regroup into a smaller number of coherent file updates.
    - Avoid one huge opaque edit touching many unrelated files. Split by concern so each batch is reviewable.

    JJ audit and recovery:
    - Treat jj as the source of truth for changed-file audit and recovery.
    - After mutating work, prefer `jj status` and `jj diff --stat`.
    - Inspect targeted `jj diff` output only for files changed by the edit or unexpected paths.
    - Do not rely on OpenCode snapshots for recovery; snapshots may be disabled for speed.

    Validation:
    - Do not run broad validation after every edit.
    - Use targeted checks only when the task requires them or the user asks.
    - Prefer one final validation checkpoint after a coherent batch instead of repeated validation after each small change.
    - If validation is expensive, long-running, interactive, or likely to stream logs, run it as an opencode-pty session with `pty_spawn`, then inspect with `pty_read` and stop with `pty_kill` when needed.

    Routing:
    - Use @fast for locating files, reading known context, simple searches, counts, and mechanical checks.
    - Use @medium for normal patch writing and implementation.
    - Use @heavy only after repeated patch failures, unclear architecture, difficult debugging, or high-risk design tradeoffs.
    - Keep @spark optional for tiny non-critical lookups and fail over to @fast without blocking.
  '';

  opencodeCommitPolicyInstructions = pkgs.writeText "opencode-commit-policy.md" ''
    # JJ-first Commit Policy

    Agents are responsible for managing commits/change boundaries when work reaches a coherent checkpoint. Use jj as the primary VCS interface when a repo uses jj.

    Default behavior:
    - Do not ask the user to commit routine completed work.
    - Create clean, coherent change boundaries proactively after completing a meaningful unit of work.
    - Prefer one jj change per coherent intent: config change, feature slice, bug fix, spec/proposal update, validation-only fix, or cleanup.
    - Keep unrelated work out of the same change.
    - If there are unrelated user changes, preserve them and avoid folding them into the agent's change.

    Before committing or describing a change:
    - Run `jj status`.
    - Run `jj diff --stat`.
    - Inspect targeted `jj diff` for changed files and any surprising paths.
    - Ensure generated/noisy files are intentional before including them.
    - If the working copy contains unrelated user work that cannot be separated safely, pause and report the conflict instead of guessing.

    Normal jj workflow:
    - Use `jj status` and `jj diff --stat` for audit.
    - Use targeted `jj diff <paths>` for review.
    - Use `jj describe -m "<message>"` to name the current coherent change when appropriate.
    - Use `jj new` to start the next clean change after describing/completing the current one when continuing with a separate unit of work.
    - If the repo also uses git remotes/bookmarks, do not move bookmarks or push unless the user asks.

    Commit message style:
    - Use imperative mood.
    - Keep the first line concise and specific.
    - Include a short body when it helps explain why, risk, validation, or scope.
    - Mention validation only when it was actually run.

    Safety boundaries:
    - `jj undo` is allowed to recover from the agent's own immediately previous mistaken jj operation when the correction is clear.
    - Do not run other destructive history or worktree operations unless explicitly asked: `jj abandon`, `jj restore`, `jj rebase`, `jj squash`, `jj split`, `jj git push`, bookmark movement, or equivalent git destructive commands.
    - Do not amend, squash, rebase, or rewrite user-controlled history unless explicitly asked.
    - Do not silently discard uncommitted/user changes.
    - If a subagent made changes, the primary agent must audit with jj before describing or advancing the change.

    Non-jj fallback:
    - If the repo is not using jj, use git only after confirming the repo state with `git status --short`.
    - Never commit unrelated user changes.
    - Do not push unless the user asks.
  '';

  opencodeRoutingInstructions = pkgs.writeText "opencode-routing-instructions.md" ''
    Prefer the OpenCode model router for work splitting. Treat yourself as the orchestrator: decompose, dispatch, then synthesize.

    Routing policy:
    - Use @spark only for tiny, non-critical, read-only context lookups when its separate subscription pool is useful.
    - If @spark fails, quota-limits, pool-limits, or feels slow, retry that exact lookup with @fast and move on.
    - Use @fast for ordinary read-only exploration: search, grep, read, count, symbol lookup, docs lookup, and AFT queries.
    - Use @fallback when Spark fails or the latest 5.5 pool appears unavailable, degraded, or unnecessarily expensive for the retry.
    - Use @medium for normal implementation on 5.5-fast: edits, refactors, tests, build fixes, config changes, and MCP-backed coding work.
    - Use @heavy only for architecture, security, performance, root-cause analysis, multi-system tradeoffs, or repeated failures.
    - Use @pro only when the user explicitly asks for the strongest model, a decision is high-stakes/irreversible, or @heavy fails.

    AFT policy:
    - In repos with AFT enabled, prefer AFT search/index tools before broad shell grep/read exploration.
    - Batch related context lookups into one delegated fast prompt when possible.

    Fast edit policy:
    - Minimize patch/write tool-call overhead. Tiny localized edits can use normal patching; medium implementation should be grouped into coherent edit batches; generated artifacts, OpenSpec files, markdown plans, skills, config snippets, and new files may use full-file writes when that is clearer and faster.
    - Prefer fewer reviewable write operations over long sequences of tiny patches.
    - Avoid one giant opaque edit touching unrelated files. Split by concern when the batch would be hard to audit.
    - Use @fast for file location and read-only prep, @medium for patch writing, and @heavy only after repeated patch failures or unclear design.

    Adaptive-thinking policy:
    - Keep reasoning low for tiny lookups and mechanical edits.
    - Raise reasoning for ambiguous debugging, architecture, security, or design choices.
    - Do not make the user think about subagents or model selection unless they ask.

    Background delegation policy:
    - Prefer opencode-background-agents for long-running, risky, parallel, or mutation-capable delegated work.
    - Use `delegate` for background tasks, then monitor with `delegation_status` and `delegation_peek` instead of waiting blindly.
    - If a background agent drifts, loops, edits unexpected files, expands scope, ignores AGENTS.md/OpenSpec rules, or starts expensive validation without permission, use `delegation_steer` once for a precise correction. If it continues, use `delegation_stop` and synthesize what happened.
    - Use `delegation_read` only after the task is done or intentionally stopped, then merge the result into the primary synthesis.
    - Prefer model-router tiers inside background prompts: @fast for read-only context, @medium for implementation, @heavy for architecture/security/perf/RCA, and @pro only for explicit break-glass work.
    - For Spark, keep the same failover rule: @spark is optional for tiny non-critical lookups; if it fails or stalls, retry with @fast.

    Subagent monitoring policy:
    - Prefer background-agent delegation over opaque built-in subagents when live polling would reduce risk.
    - Require every mutating subagent or background agent to return a concise audit packet: files changed, commands run, validation attempted, assumptions, and uncertainty.
    - After any mutating subagent returns, audit before trusting it. Prefer `jj status` and `jj diff --stat`; inspect targeted `jj diff` output for files the subagent claimed to change or any unexpected paths.
    - Treat jj as the source of truth for audit/recovery. OpenCode snapshots may be disabled to avoid duplicate internal git indexing on large or noisy repositories.
    - If the repo is not using jj, fall back to `git status --short` and targeted `git diff --stat`.
    - Bad behaviors to catch: unexpected files, broad validation without permission, repeated/looping exploration, scope expansion, ignored AGENTS.md/OpenSpec rules, edits after reporting uncertainty, or hidden generated-file churn.
    - If an audit finds drift, stop routing more work and report the mismatch before deciding whether to revert, repair, or re-dispatch.
    - Prefer small, auditable subagent tasks over one large opaque task. Ask subagents to leave checkpoints in their final response rather than relying on trust.

    Validation policy:
    - Do not run broad validation after every edit.
    - Prefer one final targeted validation checkpoint after a coherent edit batch.
    - If validation is expensive, long-running, interactive, or likely to stream logs, use opencode-pty: start with `pty_spawn`, inspect with `pty_read`, send input with `pty_write`, and stop with `pty_kill`.

    Commit policy:
    - Agents should manage jj change boundaries for coherent completed work without asking the user to do routine commits.
    - Before describing or advancing a change, audit with `jj status`, `jj diff --stat`, and targeted `jj diff` for changed or surprising paths.
    - Use `jj describe` to name the current coherent change when appropriate.
    - Use `jj new` to start the next clean change when continuing with a separate unit of work.
    - Keep unrelated user changes out of the agent's change. If separation is unsafe or ambiguous, pause and report the conflict.
    - `jj undo` is allowed to recover from the agent's own immediately previous mistaken jj operation when the correction is clear.
    - Do not push, rewrite, squash, abandon, restore, rebase, split, or move bookmarks unless explicitly asked.
  '';

in
{
  inherit
    opencodeLongRunningCommandInstructions
    opencodeAftFirstInstructions
    opencodeFastEditInstructions
    opencodeCommitPolicyInstructions
    opencodeRoutingInstructions
    ;

  paths = [
    opencodeLongRunningCommandInstructions
    opencodeAftFirstInstructions
    opencodeFastEditInstructions
    opencodeCommitPolicyInstructions
    opencodeRoutingInstructions
  ];
}
