{
  pkgs,
  lib,
  agentsPlugin,
  opencodeRuntimeSrc,
}:

let
  postgresMcp = pkgs.buildNpmPackage rec {
    pname = "postgres-mcp";
    version = "3.1.0";

    src = pkgs.fetchFromGitHub {
      owner = "neverinfamous";
      repo = "postgres-mcp";
      rev = "v${version}";
      hash = "sha256-myKnAxjYL8QnraI78QxHzULiw0/47jkZM9cGnZSni9A=";
    };

    npmDepsHash = "sha256-geu1qML9Ij2X7Ja7pU+6Tx8UMDX0lBMvCme1NuDAKlY=";
    nodejs = pkgs.nodejs_24;
  };

  opencodeModelRouterTiers = pkgs.writeText "opencode-model-router-tiers.json" (builtins.toJSON {
    activePreset = "openai-codex";
    activeMode = "normal";
    defaultTier = "medium";

    presets = {
      "openai-codex" = {
        spark = {
          model = "openai/gpt-5.3-codex-spark";
          costRatio = 0.5;
          contextWindow = 200000;
          maxTokens = 20000;
          reasoning.effort = "low";
          description = "Opportunistic Spark lane for quick read-only exploration when its separate subscription pool is available.";
          whenToUse = [
            "Tiny, non-critical read-only lookups"
            "Quick symbol or file context checks"
            "Cheap preliminary exploration before a reliable fast retry"
          ];
        };
        fast = {
          model = "openai/gpt-5.4-mini-fast";
          costRatio = 1;
          contextWindow = 200000;
          maxTokens = 20000;
          reasoning.effort = "low";
          description = "Reliable fast fallback for cheap search, grep, read, count, and lookup work.";
          whenToUse = [
            "Codebase exploration and search"
            "Simple file reads and listing"
            "AFT search, grep, count, and symbol lookup"
            "Fallback when Spark is unavailable or quota-limited"
          ];
        };
        fallback = {
          model = "openai/gpt-5.4-fast";
          costRatio = 2;
          contextWindow = 200000;
          maxTokens = 30000;
          reasoning.effort = "low";
          description = "Reliable fallback lane when Spark or the latest 5.5 pool is unavailable, degraded, or overkill.";
          whenToUse = [
            "Retrying failed Spark or fast lookups"
            "Fallback when 5.5-fast appears quota-limited or unavailable"
            "Moderate read-only investigation that needs more reliability than mini-fast"
          ];
        };
        medium = {
          model = "openai/gpt-5.5-fast";
          costRatio = 5;
          contextWindow = 200000;
          maxTokens = 40000;
          reasoning.effort = "medium";
          description = "Default latest-model implementation lane for edits, refactors, tests, and build fixes.";
          whenToUse = [
            "Feature implementation"
            "Bug fixes and build fixes"
            "Refactors, tests, and config changes"
            "MCP-backed coding tasks"
          ];
        };
        heavy = {
          model = "openai/gpt-5.5";
          costRatio = 20;
          contextWindow = 400000;
          maxTokens = 60000;
          reasoning.effort = "high";
          description = "Deep analysis lane for architecture, security, performance, RCA, and repeated failures.";
          whenToUse = [
            "Architecture and design tradeoffs"
            "Security or performance analysis"
            "Root-cause analysis"
            "Debugging after repeated failures"
            "Multi-system integration reasoning"
          ];
        };
        pro = {
          model = "openai/gpt-5.5-pro";
          costRatio = 40;
          contextWindow = 400000;
          maxTokens = 80000;
          reasoning.effort = "high";
          description = "Break-glass highest-capability lane for explicit requests, irreversible design calls, or failures after heavy analysis.";
          whenToUse = [
            "User explicitly asks for the strongest model"
            "High-stakes architecture or security decision"
            "Repeated failures after heavy analysis"
            "Cross-system migration plan with irreversible consequences"
          ];
        };
      };
    };

    tierCaps = {
      spark = 6;
      fast = 8;
      fallback = 6;
      medium = 5;
      heavy = 3;
      pro = 2;
    };

    taskPatterns = {
      spark = [
        "quick-search"
        "small-grep"
        "single-file-read"
        "symbol-lookup"
        "cheap-context"
      ];
      fast = [
        "search"
        "grep"
        "read"
        "git-info"
        "ls"
        "lookup-docs/types"
        "count"
        "exists-check"
        "rename"
      ];
      fallback = [
        "retry-after-spark-fail"
        "retry-after-latest-pool-fail"
        "moderate-context"
        "reliable-read-only"
      ];
      medium = [
        "impl-feature"
        "refactor"
        "write-tests"
        "bugfix"
        "edit-logic"
        "code-review"
        "build-fix"
        "create-file"
        "db-migrate"
        "api-endpoint"
        "config-update"
      ];
      heavy = [
        "arch-design"
        "debug-after-failures"
        "sec-audit"
        "perf-opt"
        "migrate-strategy"
        "multi-system-integration"
        "tradeoff-analysis"
        "rca"
      ];
      pro = [
        "explicit-best-model"
        "irreversible-architecture"
        "high-stakes-security"
        "heavy-failed"
        "cross-system-migration"
      ];
    };

    modes = {
      normal = {
        defaultTier = "medium";
        description = "Balanced OpenAI-only routing: 5.5-fast for everyday coding, mini/spark for exploration, 5.5/pro for escalations.";
      };
      budget = {
        defaultTier = "fast";
        description = "Aggressive context and subscription savings; prefer Spark/fast exploration, escalate only for edits or failures.";
        overrideRules = [
          "default read-only work -> @spark if tiny and non-critical, otherwise @fast"
          "if @spark errors, quota-limits, pool-limits, or stalls, retry the same prompt once with @fast, then @fallback if needed"
          "@medium only for implementation, refactors, tests, build fixes, or config changes"
          "@heavy only when requested, for architecture/security/perf/RCA, or after 2+ medium failures"
          "@pro only when explicitly requested or after @heavy fails on a high-stakes task"
          "batch related searches into one delegated prompt"
        ];
      };
      quality = {
        defaultTier = "medium";
        description = "Quality-first; use stronger Codex models more liberally while keeping cheap exploration delegated.";
        overrideRules = [
          "read-only exploration -> @fast, with @spark only for non-critical tiny lookups"
          "implementation -> @medium"
          "architecture/security/perf/RCA/repeated failure -> @heavy"
          "@pro only for explicit best-model requests or after @heavy cannot resolve a high-stakes decision"
          "prefer correctness over saving a delegation"
        ];
      };
      deep = {
        defaultTier = "heavy";
        description = "Deep analysis mode; gather context cheaply before expensive reasoning.";
        overrideRules = [
          "context gathering -> @fast, optionally @spark for tiny lookups"
          "deep analysis -> @heavy after concrete context is collected"
          "@pro only for explicit best-model requests, irreversible decisions, or after @heavy fails"
          "implementation follow-through -> @medium unless the issue remains architectural"
          "if Spark fails or is unavailable, do not retry Spark; use @fast, then @fallback if the latest pool is unavailable"
        ];
      };
    };

    fallback.presets."openai-codex".openai = [ "openai-codex" ];

    rules = [
      "[tier:X] tag in plan -> delegate to X"
      "For tiny non-critical read-only lookups, @spark is allowed first."
      "Spark uses a different subscription pool: if @spark errors, quota-limits, pool-limits, or stalls, retry the same prompt with @fast and continue."
      "If the latest 5.5 pool appears unavailable or degraded, use @fallback instead of blocking."
      "Do not block the user on Spark availability."
      "Read-only exploration -> @fast by default; implementation -> @medium; architecture/security/perf/RCA/repeated failure -> @heavy; explicit highest-capability escalation -> @pro."
      "Use AFT search/index tools before broad grep/read when a repository has AFT enabled."
      "Use adaptive-thinking to lower reasoning for trivial lookups and raise it only for deep design/debug decisions."
      "For patching, minimize tool-call overhead: tiny localized edits may use normal patches; generated/new artifacts may use full-file writes; medium implementation should be batched into coherent reviewable edit groups."
      "Do not run broad validation after every edit. Prefer one final targeted validation checkpoint after a coherent batch, unless the user explicitly asks for more."
      "Agents should manage jj change boundaries for coherent completed work: audit with `jj status`, `jj diff --stat`, and targeted `jj diff`, then use `jj describe` and `jj new` when appropriate. `jj undo` is allowed to recover from the agent's own immediately previous mistaken jj operation. Do not push, rewrite, squash, abandon, restore, rebase, or move bookmarks unless explicitly asked."
      "For long-running, risky, parallel, or mutation-capable delegated work, prefer opencode-background-agents so the primary can poll with delegation_status, inspect with delegation_peek, steer with delegation_steer, stop with delegation_stop, and read final output with delegation_read."
      "For mutating subagents, require a final report with files changed, commands run, validation attempted, and any uncertainty."
      "After any mutating subagent returns, the primary agent must audit the worktree before trusting the result: prefer `jj status` and `jj diff --stat`, then inspect targeted diffs for surprising changes."
      "If a subagent edits unexpected files, runs broad validation without permission, loops, ignores scope, or reports uncertainty, stop and synthesize the issue before dispatching more work."
      "Primary agent synthesizes; delegated agents execute."
    ];
  });

  opencodeRuntime = pkgs.buildNpmPackage {
    pname = "opencode-runtime";
    version = "0.1.0";
    src = opencodeRuntimeSrc;
    npmDepsHash = "sha256-L7x+w3uiLJIFB56q4mN7TZnpF0lzqz0CYNBiY2LJ1v8=";
    nodejs = pkgs.nodejs_24;
    npmFlags = [ "--legacy-peer-deps" ];
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib" "$out/bin"
      cp -R node_modules "$out/lib/node_modules"
      chmod -R u+w "$out/lib/node_modules"

      mkdir -p "$out/lib/node_modules/@becker"
      ln -s "${agentsPlugin.package}" "$out/lib/node_modules/@becker/opencode-agents-md-context"

      if [ -d "$out/lib/node_modules/.bin" ]; then
        for bin in "$out/lib/node_modules/.bin"/*; do
          [ -e "$bin" ] || continue
          ln -s "$bin" "$out/bin/$(basename "$bin")"
        done
      fi

      if [ -d "$out/lib/node_modules/opencode-model-router" ]; then
        install -m 0644 "${opencodeModelRouterTiers}" "$out/lib/node_modules/opencode-model-router/tiers.json"
      fi

      if [ -d "$out/lib/node_modules/opencode-adaptive-thinking" ]; then
        cat > "$out/lib/node_modules/opencode-adaptive-thinking/default-wrapper.js" <<'EOF'
export { AdaptiveThinkingPlugin as default } from "./dist/index.js";
export * from "./dist/index.js";
EOF
        cat > "$out/lib/node_modules/opencode-adaptive-thinking/package.json" <<'EOF'
{
  "name": "opencode-adaptive-thinking",
  "version": "0.1.4",
  "type": "module",
  "main": "./default-wrapper.js",
  "exports": {
    ".": {
      "import": "./default-wrapper.js",
      "default": "./default-wrapper.js"
    }
  },
  "dependencies": {
    "zod": "^4.4.3"
  },
  "peerDependencies": {
    "@opencode-ai/plugin": ">=1",
    "@opencode-ai/sdk": ">=1"
  }
}
EOF
      fi

      OUT="$out" node <<'EOF'
const fs = require("node:fs");
const out = process.env.OUT;

for (const rel of [
  "/lib/node_modules/@cortexkit/opencode-magic-context/src/shared/conflict-detector.ts",
  "/lib/node_modules/@cortexkit/opencode-magic-context/dist/index.js"
]) {
  const file = out + rel;
  if (!fs.existsSync(file)) continue;
  const source = fs.readFileSync(file, "utf8");
  const next = source.replace(
    /DCP_PACKAGE_NAMES\s*=\s*new Set\(\[\s*["']@tarquinen\/opencode-dcp["']\s*\]\)/g,
    "DCP_PACKAGE_NAMES = new Set([])"
  );
  if (next !== source) fs.writeFileSync(file, next);
}

const aggregateReplacement = [
  "function readCompressionAggregate(value) {",
  "  const aggregate = asRecord(value);",
  "  const events = Math.max(0, Math.trunc(readNumber(aggregate.events)));",
  "  const original = Math.max(0, Math.round(readNumber(aggregate.original_tokens)));",
  "  let compressed = Math.max(0, Math.round(readNumber(aggregate.compressed_tokens)));",
  "  let savings = Math.max(0, Math.round(readNumber(aggregate.savings_tokens)));",
  "  if (original <= 0) {",
  "    compressed = 0;",
  "    savings = 0;",
  "  } else {",
  "    if (compressed <= 0 && savings > 0) {",
  "      compressed = original - Math.min(savings, original);",
  "    }",
  "    if (savings <= 0 && compressed > 0) {",
  "      savings = original - Math.min(compressed, original);",
  "    }",
  "    compressed = Math.min(compressed, original);",
  "    savings = Math.min(savings, original);",
  "    if (compressed + savings > original) {",
  "      savings = original - compressed;",
  "    }",
  "  }",
  "  return {",
  "    events,",
  "    original_tokens: original,",
  "    compressed_tokens: compressed,",
  "    savings_tokens: savings",
  "  };",
  "}"
].join("\n");

for (const rel of [
  "/lib/node_modules/@cortexkit/aft-opencode/dist/tui.js",
  "/lib/node_modules/@cortexkit/aft-opencode/dist/index.js"
]) {
  const file = out + rel;
  if (!fs.existsSync(file)) continue;
  const source = fs.readFileSync(file, "utf8");
  const next = source.replace(
    /function readCompressionAggregate\(value\) \{[\s\S]*?\n\}/,
    aggregateReplacement
  );
  if (next !== source) fs.writeFileSync(file, next);
}

const zigMcp = out + "/lib/node_modules/zig-mcp/dist/mcp.js";
if (fs.existsSync(zigMcp)) {
  const source = fs.readFileSync(zigMcp, "utf8");
  const marker = "mcpServer.setResourceRequestHandlers();";
  const next = source.includes(marker)
    ? source
    : source.replace(
        "    await registerAllTools(mcpServer, builtinFunctions, stdSources);\n",
        [
          "    await registerAllTools(mcpServer, builtinFunctions, stdSources);",
          "    // OpenCode probes optional MCP surfaces during startup. zig-mcp",
          "    // intentionally exposes only tools, so register empty handlers for",
          "    // resources/prompts to avoid noisy Method not found errors.",
          "    mcpServer.setResourceRequestHandlers();",
          "    mcpServer.setPromptRequestHandlers();",
          ""
        ].join("\n")
      );
  if (next !== source) fs.writeFileSync(zigMcp, next);
}
EOF

      make_cache_root() {
        cache_name="$1"
        package_name="$2"
        root="$out/cache-packages/$cache_name"
        package_root="$out/lib/node_modules/$package_name"

        mkdir -p "$root/node_modules"
        package_parent="$(dirname "$package_name")"
        if [ "$package_parent" != "." ]; then
          mkdir -p "$root/node_modules/$package_parent"
        fi

        printf '{"private":true,"dependencies":{"%s":"*"}}\n' "$package_name" > "$root/package.json"
        ln -s "$package_root" "$root/node_modules/$package_name"
      }

      make_cache_root "@aeondave/opencode-background-agents@latest" "@aeondave/opencode-background-agents"
      make_cache_root "@aeondave/opencode-background-agents" "@aeondave/opencode-background-agents"
      make_cache_root "@cortexkit/aft-opencode@0.46.0" "@cortexkit/aft-opencode"
      make_cache_root "@cortexkit/aft-opencode@latest" "@cortexkit/aft-opencode"
      make_cache_root "@cortexkit/aft-opencode" "@cortexkit/aft-opencode"
      make_cache_root "@cortexkit/opencode-magic-context@latest" "@cortexkit/opencode-magic-context"
      make_cache_root "@cortexkit/opencode-magic-context" "@cortexkit/opencode-magic-context"
      make_cache_root "@ramtinj95/opencode-tokenscope@latest" "@ramtinj95/opencode-tokenscope"
      make_cache_root "@tarquinen/opencode-dcp@latest" "@tarquinen/opencode-dcp"
      make_cache_root "@tarquinen/opencode-dcp" "@tarquinen/opencode-dcp"
      make_cache_root "opencode-adaptive-thinking@latest" "opencode-adaptive-thinking"
      make_cache_root "opencode-adaptive-thinking" "opencode-adaptive-thinking"
      make_cache_root "opencode-model-router@latest" "opencode-model-router"
      make_cache_root "opencode-model-router" "opencode-model-router"
      make_cache_root "opencode-pty@latest" "opencode-pty"
      make_cache_root "opencode-pty" "opencode-pty"
      make_cache_root "openrtk@latest" "openrtk"

      runHook postInstall
    '';
  };

  opencodeRuntimeNodeModulePackages = [
    "@aeondave/opencode-background-agents"
    "@becker/opencode-agents-md-context"
    "@cortexkit/aft"
    "@cortexkit/aft-opencode"
    "@cortexkit/opencode-magic-context"
    "@opencode-ai/plugin"
    "@opencode-ai/sdk"
    "@ramtinj95/opencode-tokenscope"
    "@tarquinen/opencode-dcp"
    "opencode-adaptive-thinking"
    "opencode-model-router"
    "opencode-pty"
    "openrtk"
    "zig-mcp"
  ];

  opencodeRuntimeCachePackages = [
    "@aeondave/opencode-background-agents@latest"
    "@aeondave/opencode-background-agents"
    "@cortexkit/aft-opencode@0.46.0"
    "@cortexkit/aft-opencode@latest"
    "@cortexkit/aft-opencode"
    "@cortexkit/opencode-magic-context@latest"
    "@cortexkit/opencode-magic-context"
    "@ramtinj95/opencode-tokenscope@latest"
    "@tarquinen/opencode-dcp@latest"
    "@tarquinen/opencode-dcp"
    "opencode-adaptive-thinking@latest"
    "opencode-adaptive-thinking"
    "opencode-model-router@latest"
    "opencode-model-router"
    "opencode-pty@latest"
    "opencode-pty"
    "openrtk@latest"
  ];

  opencodePatched = pkgs.opencode.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      pkgs.perl
    ];

    postPatch = (old.postPatch or "") + ''
      # OpenCode 1.18 moved its interactive UI into the standalone tui package.
      runtime_file="packages/opencode/src/plugin/tui/runtime.ts"
      session_file="packages/tui/src/routes/session/index.tsx"
      thinking_file="packages/tui/src/context/thinking.ts"
      run_entry_body_file="packages/opencode/src/cli/cmd/run/entry.body.ts"
      run_session_data_file="packages/opencode/src/cli/cmd/run/session-data.ts"

      perl -0pi -e 's#import \{ runtimeModules as keymapRuntimeModules \} from "\@opentui/keymap/runtime-modules"#import { runtimeModules as keymapRuntimeModules } from "\@opentui/keymap/runtime-modules"\nimport * as solidJsxRuntime from "\@opentui/solid/jsx-runtime"\nimport * as solidJsxDevRuntime from "\@opentui/solid/jsx-dev-runtime"#' "$runtime_file"
      perl -0pi -e 's#ensureRuntimePluginSupport\(\{ additional: keymapRuntimeModules \}\)#ensureRuntimePluginSupport({\n  additional: {\n    ...keymapRuntimeModules,\n    "\@opentui/solid/jsx-runtime": solidJsxRuntime,\n    "\@opentui/solid/jsx-dev-runtime": solidJsxDevRuntime,\n  },\n  rewrite: {\n    nodeModulesRuntimeSpecifiers: true,\n    nodeModulesBareSpecifiers: true,\n  },\n})#' "$runtime_file"

      grep -q '"@opentui/solid/jsx-runtime": solidJsxRuntime' "$runtime_file"
      grep -q 'nodeModulesBareSpecifiers: true' "$runtime_file"

      perl -0pi -e 's#\.replace\("\[REDACTED\]", ""\)\.trim\(\)#.replace("[REDACTED]", "").replace(/<!--\\s*-->/g, "").trim()#g' "$session_file"
      grep -Fq 'replace(/<!--\s*-->/g, "")' "$session_file"
      perl -0pi -e 's#const content = text\.trim\(\)#const content = text.replace(/<!--\\s*-->/g, "").trim()#' "$thinking_file"
      grep -Fq 'text.replace(/<!--\s*-->/g, "")' "$thinking_file"
      perl -0pi -e 's#const clean = raw\.replace\(/\\\[REDACTED\\\]/g, ""\)#const clean = raw.replace(/\\[REDACTED\\]/g, "").replace(/<!--\\s*-->/g, "")#' "$run_entry_body_file"
      grep -Fq 'replace(/<!--\s*-->/g, "")' "$run_entry_body_file"
      perl -0pi -e 's#chunk = `Thinking: \$\{chunk\.replace\(/\\\[REDACTED\\\]/g, ""\)\}`#chunk = `Thinking: \''${chunk.replace(/\\[REDACTED\\]/g, "").replace(/<!--\\s*-->/g, "")}`#' "$run_session_data_file"
      grep -Fq 'replace(/<!--\s*-->/g, "")' "$run_session_data_file"
    '';
  });

  opencodeWithTooling = pkgs.runCommand "opencode-with-tooling" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p "$out/bin" "$out/libexec"

    makeWrapper "${opencodePatched}/bin/opencode" "$out/libexec/opencode" \
      --prefix PATH : "${lib.makeBinPath [
        pkgs.direnv
        pkgs.git
        pkgs.jujutsu
        pkgs.ripgrep
        pkgs.fd
        pkgs.jq
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.findutils
        postgresMcp
        opencodeRuntime
      ]}" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        pkgs.stdenv.cc.cc.lib
      ]}"

    cat > "$out/bin/opencode" <<EOF
    #!${pkgs.runtimeShell}
    if [ -z "\''${OPENCODE_DIRENV_WRAPPED:-}" ] && command -v direnv >/dev/null 2>&1 && [ -f .envrc ]; then
      export OPENCODE_DIRENV_WRAPPED=1
      if direnv exec "\$PWD" true >/dev/null 2>&1; then
        exec direnv exec "\$PWD" "$out/libexec/opencode" "\$@"
      fi
    fi
    exec "$out/libexec/opencode" "\$@"
    EOF
    chmod +x "$out/bin/opencode"

    ln -s "${postgresMcp}/bin/postgres-mcp" "$out/bin/postgres-mcp"
  '';

in
{
  inherit
    postgresMcp
    opencodeModelRouterTiers
    opencodeRuntime
    opencodeRuntimeNodeModulePackages
    opencodeRuntimeCachePackages
    opencodePatched
    opencodeWithTooling
    ;
}
