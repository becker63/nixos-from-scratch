{ pkgs, sourceRoot ? ../. }:
let
  e2e = pkgs.writeShellApplication {
    name = "opencode-context-stack-e2e";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      python3
    ];
    text = ''
      set -euo pipefail

      mode="runtime"
      source_root="${sourceRoot}"

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --source-only)
            mode="source"
            shift
            ;;
          --source-root)
            source_root="$2"
            shift 2
            ;;
          --runtime)
            mode="runtime"
            shift
            ;;
          *)
            echo "usage: opencode-context-stack-e2e [--source-only] [--source-root PATH] [--runtime]" >&2
            exit 2
            ;;
        esac
      done

      export OPENCODE_CONTEXT_STACK_MODE="$mode"
      export OPENCODE_CONTEXT_STACK_SOURCE_ROOT="$source_root"

      python3 <<'PY'
      import json
      import os
      import pathlib
      import shutil
      import sys

      mode = os.environ["OPENCODE_CONTEXT_STACK_MODE"]
      source_root = pathlib.Path(os.environ["OPENCODE_CONTEXT_STACK_SOURCE_ROOT"])
      failures = []

      def fail(message):
          failures.append(message)

      def ok(message):
          print(f"ok: {message}")

      def require(condition, message):
          if not condition:
              fail(message)

      def read_text(path):
          try:
              return path.read_text(encoding="utf-8", errors="replace")
          except FileNotFoundError:
              fail(f"missing file: {path}")
              return ""

      def read_text_if_exists(path):
          try:
              return path.read_text(encoding="utf-8", errors="replace")
          except FileNotFoundError:
              return ""

      def load_json(path):
          text = read_text(path)
          if not text:
              return {}
          try:
              return json.loads(text)
          except json.JSONDecodeError as exc:
              fail(f"{path} is not parseable JSON/JSONC emitted by Nix: {exc}")
              return {}

      def json_strings(value):
          if isinstance(value, str):
              yield value
          elif isinstance(value, list):
              for item in value:
                  yield from json_strings(item)
          elif isinstance(value, dict):
              for item in value.values():
                  yield from json_strings(item)

      def first_existing(paths):
          for path in paths:
              if path.exists():
                  return path
          return None

      def check_source():
          opencode_source_paths = sorted((source_root / "modules/home/opencode").glob("*.nix"))
          opencode_sources = "\n".join(read_text(path) for path in opencode_source_paths)
          flake_wiring_paths = [source_root / "checks/default.nix"]
          flake_wiring_paths.extend(sorted((source_root / "outputs/perSystem").glob("*.nix")))
          flake_wiring_sources = "\n".join(read_text(path) for path in flake_wiring_paths)
          opencode_runtime_package = read_text(source_root / "packages/opencode-runtime/package.json")

          required_home_strings = {
              "@cortexkit/aft-opencode@0.46.0": "AFT OpenCode plugin is pinned in the OpenCode stack",
              "@tarquinen/opencode-dcp@latest": "DCP plugin is declared",
              "@cortexkit/opencode-magic-context@latest": "Magic Context plugin is declared from npm",
              "opencode-pty@latest": "OpenCode PTY plugin is declared for long-running background commands",
              "opencodeRuntime = pkgs.buildNpmPackage": "OpenCode npm stack is built as a pure Nix npm derivation",
              "npmDepsHash = \"sha256-L7x+w3uiLJIFB56q4mN7TZnpF0lzqz0CYNBiY2LJ1v8=\";": "OpenCode runtime npm dependencies are hash-pinned",
              "''${runtime.opencodeRuntime}/bin/zig-mcp": "zig-mcp is sourced from the pure OpenCode runtime",
              "home.activation.installOpenCodeRuntime": "OpenCode activation only links the pure runtime and updates state",
              "Prefer `pty_spawn` for detached local command sessions": "OpenCode instructions prefer opencode-pty for long-running local commands",
              "Use opencode-background-agents for delegated agent work": "OpenCode instructions separate delegated agent work from local PTY sessions",
              "search_index = true;": "AFT indexing is enabled in the generated config",
              "semantic_search = true;": "AFT semantic search is enabled in the generated config",
              "debug = true;": "DCP debug logging is enabled for diagnosis",
              "allowSubAgents = true;": "DCP processes router/subagent sessions",
              "showCompression = true;": "DCP shows compression content so activity is visible",
              "minContextLimit = \"25%\";": "DCP lower automatic compression threshold is configured",
              "maxContextLimit = \"50%\";": "DCP upper automatic compression threshold is configured",
              "nudgeFrequency = 1;": "DCP nudges on every context fetch once over threshold",
              "iterationNudgeThreshold = 8;": "DCP begins iteration nudges before sessions get huge",
              "nudgeForce = \"strong\";": "DCP uses strong nudges for automatic compression",
              "\"cortexkit/aft.jsonc\".source = aftConfig;": "AFT config is linked into XDG config",
              "\"cortexkit/magic-context.jsonc\".source = magicContextConfig;": "Magic Context user config is linked into XDG config",
              "model = \"openai/gpt-5.4-mini-fast\";": "Magic Context historian model is set at user scope",
              "\"opencode/dcp.jsonc\".source = opencodeDcpConfig;": "DCP config is linked into XDG config",
              "\"opencode/opencode.json\".source = opencodeConfig;": "OpenCode config is linked into XDG config",
              "\"opencode/tui.jsonc\".source = opencodeTuiConfig;": "OpenCode TUI config is linked into XDG config",
              "\"opencode/tui-preferences.jsonc\".source = opencodeTuiPreferencesConfig;": "OpenCode TUI preferences are linked into XDG config",
              "forceToTop = true;": "Magic Context sidebar is forced near the top",
              "DCP_PACKAGE_NAMES = new Set([])": "Magic Context DCP conflict detector is neutralized without a derivation",
              "replace(/<!--\\\\s*-->/g, \"\")": "OpenCode thinking renderer strips empty HTML comment placeholders",
              ".variant[\"openai/gpt-5.5-fast\"] = \"high\"": "OpenCode primary fast model keeps high-effort reasoning summaries without changing router models",
          }

          required_runtime_package_strings = {
              "\"@cortexkit/aft\": \"0.46.0\"": "AFT core package is pinned in the pure runtime",
              "\"@cortexkit/aft-opencode\": \"0.46.0\"": "AFT OpenCode plugin is pinned in the pure runtime",
              "\"@cortexkit/opencode-magic-context\": \"0.31.5\"": "Magic Context plugin is pinned in the pure runtime",
              "\"@tarquinen/opencode-dcp\": \"3.1.14\"": "DCP plugin is pinned in the pure runtime",
              "\"opencode-pty\": \"0.3.6\"": "OpenCode PTY plugin is pinned in the pure runtime",
              "\"zig-mcp\": \"1.4.1\"": "zig-mcp is pinned in the pure runtime",
          }

          forbidden_home_strings = {
              "opencodeNpmPackages": "OpenCode package set should not be installed imperatively by activation",
              "installOpenCodeTooling": "OpenCode tooling should not be installed imperatively by activation",
              "installOpenCodeModelRouterConfig": "OpenCode plugin patching should not run against mutable npm installs",
              "npm install -g --legacy-peer-deps": "OpenCode activation should not invoke npm global installs",
              "opencodeMagicContextExperimentalPlugin": "Magic Context derivation should be removed",
              "opencodeMagicContextPatchedPlugin": "Magic Context file-package alias should be removed",
              "opencodeMagicContextBackfill": "Magic Context backfill activation should be removed",
              "@cortexkit/opencode-magic-context@file://": "Magic Context should not be pinned to a file:// package",
              "createAftDashboardSlot": "AFT dashboard slot injection should be removed",
              "AFT Magic": "synthetic AFT/Magic dashboard label should be removed",
              "use AFT's background bash and PTY support instead of blocking the foreground shell": "AFT should not be preferred over opencode-pty for long-running local commands",
              "use AFT-backed background bash/PTY support": "AFT background shell should not be the primary long-running command policy",
          }

          for needle, description in required_home_strings.items():
              require(needle in opencode_sources, f"OpenCode modules missing {description}: {needle}")
          for needle, description in required_runtime_package_strings.items():
              require(needle in opencode_runtime_package, f"opencode-runtime package missing {description}: {needle}")
          for needle, description in forbidden_home_strings.items():
              require(needle not in opencode_sources, f"OpenCode modules still contain {description}: {needle}")

          required_flake_strings = {
              "opencodeContext = import ./opencode-context-stack-e2e.nix": "OpenCode context stack e2e derivation import",
              "opencode-context-stack-e2e = checkSuite.opencodeContext.package;": "OpenCode context stack package export",
              "opencode-context-stack-e2e = checkSuite.opencodeContext.check;": "OpenCode context stack check export",
              "outputs'.packages.opencode-context-stack-e2e": "OpenCode context stack app export",
          }
          for needle, description in required_flake_strings.items():
              require(needle in flake_wiring_sources, f"flake wiring missing {description}: {needle}")

          if not failures:
              ok("source wiring declares upstream Magic Context, DCP, and AFT without derivation/dashboard injections")

      def check_runtime():
          home = pathlib.Path(os.environ.get("HOME", ""))
          require(bool(str(home)), "HOME is not set")

          opencode = load_json(home / ".config/opencode/opencode.json")
          tui = load_json(home / ".config/opencode/tui.jsonc")
          tui_prefs = load_json(home / ".config/opencode/tui-preferences.jsonc")
          dcp = load_json(home / ".config/opencode/dcp.jsonc")
          aft = load_json(home / ".config/cortexkit/aft.jsonc")
          magic_context = load_json(home / ".config/cortexkit/magic-context.jsonc")
          model_state = load_json(home / ".local/state/opencode/model.json")

          opencode_strings = "\n".join(json_strings(opencode))
          tui_strings = "\n".join(json_strings(tui))
          cache = home / ".cache/opencode/packages"
          npm_global = home / ".npm-global/lib/node_modules"

          for plugin in [
              "@cortexkit/aft-opencode@0.46.0",
              "@tarquinen/opencode-dcp@latest",
              "@cortexkit/opencode-magic-context@latest",
              "opencode-pty@latest",
          ]:
              require(plugin in opencode_strings, f"OpenCode config does not declare plugin {plugin}")
              require(plugin in tui_strings, f"OpenCode TUI config does not declare external plugin {plugin}")

          require("@cortexkit/opencode-magic-context@file://" not in opencode_strings, "OpenCode config still pins Magic Context to a file:// package")
          require("@cortexkit/opencode-magic-context@file://" not in tui_strings, "OpenCode TUI config still pins Magic Context to a file:// package")
          require(opencode.get("model") == "openai/gpt-5.5-fast", "OpenCode default model should stay on 5.5-fast for router/orchestrator behavior")
          variants = model_state.get("variant", {})
          require(variants.get("openai/gpt-5.5-fast") == "high", "OpenCode primary 5.5-fast variant should be high so thinking summaries are surfaced")
          require(variants.get("openai/gpt-5.5") == "high", "OpenCode full 5.5 variant should remain high for heavy reasoning summaries")

          magic_prefs = tui_prefs.get("magic-context", {})
          require(magic_prefs.get("forceToTop") is True, "Magic Context TUI prefs should force the sidebar panel near the top")
          require(magic_prefs.get("collapsed") is False, "Magic Context TUI prefs should keep the panel expanded")
          require(magic_prefs.get("startCollapsed") is False, "Magic Context TUI prefs should not start collapsed")
          require(magic_prefs.get("header", {}).get("label") == "Magic Context", "Magic Context TUI prefs should preserve the visible header label")
          sections = magic_prefs.get("sections", {})
          for section in ["historian", "memory", "status", "dreamer", "stats"]:
              require(sections.get(section) is True, f"Magic Context TUI section {section} should be visible")

          compaction = opencode.get("compaction", {})
          require(compaction.get("auto") is False, "OpenCode native compaction auto mode should stay disabled while DCP owns compression")
          require(compaction.get("prune") is False, "OpenCode native pruning should stay disabled while DCP owns compression")

          require(dcp.get("compress", {}).get("mode") == "range", "DCP compress.mode should be range")
          require(dcp.get("enabled") is True, "DCP should be explicitly enabled")
          require(dcp.get("debug") is True, "DCP debug logging should be enabled")
          require(dcp.get("pruneNotification") == "detailed", "DCP pruneNotification should be detailed")
          require(dcp.get("pruneNotificationType") == "chat", "DCP pruneNotificationType should be chat")
          require(dcp.get("experimental", {}).get("allowSubAgents") is True, "DCP should process router/subagent sessions")
          require(dcp.get("compress", {}).get("showCompression") is True, "DCP should show compression content in chat notifications")
          require(dcp.get("compress", {}).get("minContextLimit") == "25%", "DCP minContextLimit should be 25%")
          require(dcp.get("compress", {}).get("maxContextLimit") == "50%", "DCP maxContextLimit should be 50%")
          require(dcp.get("compress", {}).get("nudgeFrequency") == 1, "DCP nudgeFrequency should be 1")
          require(dcp.get("compress", {}).get("iterationNudgeThreshold") == 8, "DCP iterationNudgeThreshold should be 8")
          require(dcp.get("compress", {}).get("nudgeForce") == "strong", "DCP nudgeForce should be strong")
          require(dcp.get("manualMode", {}).get("enabled") is False, "DCP manualMode.enabled should be false")

          require(aft.get("enabled") is True, "AFT config enabled should be true")
          require(aft.get("search_index") is True, "AFT search_index should be true")
          require(aft.get("semantic_search") is True, "AFT semantic_search should be true")
          bash = aft.get("bash", {})
          for key in ["enabled", "rewrite", "compress", "background"]:
              require(bash.get(key) is True, f"AFT bash.{key} should be true")

          require(magic_context.get("enabled") is True, "Magic Context user config enabled should be true")
          require(
              magic_context.get("historian", {}).get("model") == "openai/gpt-5.4-mini-fast",
              "Magic Context historian.model should be set in the user-level CortexKit config",
          )

          roots = {
              "AFT OpenCode plugin": [
                  cache / "@cortexkit/aft-opencode@0.46.0/node_modules/@cortexkit/aft-opencode",
                  cache / "@cortexkit/aft-opencode@latest/node_modules/@cortexkit/aft-opencode",
                  cache / "@cortexkit/aft-opencode/node_modules/@cortexkit/aft-opencode",
                  home / ".config/opencode/node_modules/@cortexkit/aft-opencode",
                  npm_global / "@cortexkit/aft-opencode",
              ],
              "DCP plugin": [
                  cache / "@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp",
                  cache / "@tarquinen/opencode-dcp/node_modules/@tarquinen/opencode-dcp",
                  home / ".config/opencode/node_modules/@tarquinen/opencode-dcp",
                  npm_global / "@tarquinen/opencode-dcp",
              ],
              "Magic Context plugin": [
                  cache / "@cortexkit/opencode-magic-context@latest/node_modules/@cortexkit/opencode-magic-context",
                  cache / "@cortexkit/opencode-magic-context/node_modules/@cortexkit/opencode-magic-context",
                  home / ".config/opencode/node_modules/@cortexkit/opencode-magic-context",
                  npm_global / "@cortexkit/opencode-magic-context",
              ],
              "AFT core package": [
                  npm_global / "@cortexkit/aft",
                  home / ".config/opencode/node_modules/@cortexkit/aft",
              ],
              "OpenCode PTY plugin": [
                  cache / "opencode-pty@latest/node_modules/opencode-pty",
                  cache / "opencode-pty/node_modules/opencode-pty",
                  home / ".config/opencode/node_modules/opencode-pty",
                  npm_global / "opencode-pty",
              ],
          }

          existing_roots = {}
          for label, paths in roots.items():
              root = first_existing(paths)
              require(root is not None, f"{label} package root was not found in OpenCode cache/config/npm-global")
              if root is not None:
                  existing_roots[label] = root

          for label in ["AFT OpenCode plugin", "Magic Context plugin"]:
              root = existing_roots.get(label)
              if root is None:
                  continue
              package_text = "\n".join([
                  read_text_if_exists(root / "src/tui/index.tsx"),
                  read_text_if_exists(root / "src/tui/sidebar.tsx"),
                  read_text_if_exists(root / "src/shared/conflict-detector.ts"),
                  read_text_if_exists(root / "dist/tui.js"),
                  read_text_if_exists(root / "dist/index.js"),
              ])
              require("AFT Magic" not in package_text, f"{label} still contains the synthetic AFT Magic dashboard label: {root}")
              require("createAftDashboardSlot" not in package_text, f"{label} still contains the synthetic AFT dashboard slot: {root}")
              require("opencode-magic-context-presence" not in package_text, f"{label} still contains the synthetic Magic Context dashboard slot: {root}")
              if label == "Magic Context plugin":
                  require(
                      'DCP_PACKAGE_NAMES = new Set(["@tarquinen/opencode-dcp"])' not in package_text,
                      f"{label} still treats DCP as a conflicting package: {root}",
                  )
                  require(
                      "DCP_PACKAGE_NAMES = new Set([])" in package_text,
                      f"{label} does not have the DCP conflict package set neutralized: {root}",
                  )

          aft_binary = shutil.which("aft") or str(home / ".npm-global/bin/aft")
          require(pathlib.Path(aft_binary).exists(), "aft binary was not found on PATH or in ~/.npm-global/bin")

          if not failures:
              ok("runtime OpenCode config declares upstream Magic Context, DCP, and AFT")
              ok("DCP owns visible automatic compression and native OpenCode compaction is disabled")
              ok("AFT indexing, semantic search, and bash transparency are enabled")
              ok("installed packages do not contain the synthetic dashboard canary code")

      if mode == "source":
          check_source()
      elif mode == "runtime":
          check_runtime()
      else:
          fail(f"unknown mode: {mode}")

      if failures:
          print("OpenCode context stack e2e failed:", file=sys.stderr)
          for item in failures:
              print(f"- {item}", file=sys.stderr)
          sys.exit(1)
      PY
    '';
  };

  check = pkgs.runCommand "opencode-context-stack-e2e-check" {
    nativeBuildInputs = [ e2e ];
  } ''
    set -euo pipefail
    opencode-context-stack-e2e --source-only --source-root ${sourceRoot}
    mkdir -p "$out"
    echo ok > "$out/result"
  '';
in
{
  package = e2e;
  inherit check;
}
