# Eval-assert layer owning the Factory/Droid/Jev invariant family: the
# .factory/AGENTS.md usage policy, the conceptual-escalator droid, the
# configureFactory activation wiring, the merge tool's model-routing
# literals, and the portable exposure of the Factory packages.
#
# Realization class: EVAL-ASSERT. Everything is asserted while the values
# in this file are evaluated (nix flake show forces them); the derivation
# is a trivial marker that never needs to build. Runtime merge semantics
# are owned by factory-config's unittest suite, which runs on every build
# of that package.
{
  config,
  pkgs,
  # The aarch64 checks wiring forwards the flake's package set so the
  # exposure asserts can fire. Importers that never force this check
  # (packages.nix's check-suite wrapper packages) may leave it unset.
  portablePackages ? null,
}:

let
  lib = pkgs.lib;

  expect =
    condition: message:
    assert lib.assertMsg condition message;
    true;

  homeConfig = config.home-manager.users.becker;

  # The same derivation the home module registers, built from the same host
  # pkgs: the activation must pass exactly this store path as --jev-command.
  jevMcp = pkgs.callPackage ../packages/jev-mcp { };

  # Eval-only source reads; nothing here is realized.
  mergeSource = builtins.readFile ../packages/factory-config/factory-config-merge.py;
  agentsText = homeConfig.home.file.".factory/AGENTS.md".text or "";
  escalatorText = homeConfig.home.file.".factory/droids/conceptual-escalator.md".text or "";

  activations = homeConfig.home.activation or { };
  activation = activations.configureFactory or null;
  activationData = if activation == null then "" else activation.data or "";
  activationAfter = if activation == null then [ ] else activation.after or [ ];

  # hasInfix compiles its needle into a builtins.match regex, which Nix
  # refuses for strings carrying store-path context — so the jev-command
  # argument is split out and compared with hasPrefix instead.
  jevArgs = lib.strings.splitString "--jev-command " activationData;
  jevCommandArg = if builtins.length jevArgs > 1 then builtins.elemAt jevArgs 1 else "";

  factoryDir = "${homeConfig.home.homeDirectory}/.factory";
  jevCommand = "${jevMcp}/bin/jev-mcp";

  portableNames = if portablePackages == null then [ ] else builtins.attrNames portablePackages;

  present = condition: if condition then "present" else "missing";

  row = name: pass: expected: {
    name = "Factory: ${name}";
    inherit pass expected;
    actual = present pass;
  };

  infixRow =
    label: needle: haystack:
    row label (lib.hasInfix needle haystack) "contains: ${needle}";

  # Routing pairs share the "<key>Model"/"<key>ReasoningEffort" shape of
  # SETTINGS_DEFAULTS in factory-config-merge.py; the top-level pair is
  # just another instance.
  routeRow =
    label: modelKey: model: effortKey: effort:
    row "routing: ${label}" (
      lib.hasInfix "\"${modelKey}\": \"${model}\"" mergeSource
      && lib.hasInfix "\"${effortKey}\": \"${effort}\"" mergeSource
    ) "${modelKey} = ${model}, ${effortKey} = ${effort}";

  agentsFile = homeConfig.home.file ? ".factory/AGENTS.md";
  escalatorFile = homeConfig.home.file ? ".factory/droids/conceptual-escalator.md";

  checks = [
    # Home files: the usage policy and the escalator droid.
    (row "AGENTS.md is installed for becker" agentsFile "home.file \".factory/AGENTS.md\"")
    (infixRow "AGENTS.md grants Jev bounded semantic decisions only"
      "Use it freely for useful bounded semantic choice, noul, or score judgments"
      agentsText
    )
    (infixRow "AGENTS.md forbids Jev for generation, arithmetic, and model selection"
      "do not use Jev for generation, arithmetic, or Factory model selection"
      agentsText
    )
    (row "conceptual-escalator droid is installed for becker" escalatorFile
      "home.file \".factory/droids/conceptual-escalator.md\""
    )
    (infixRow "escalator droid reviews on gpt-5.6-sol" "model: gpt-5.6-sol" escalatorText)
    (infixRow "escalator droid reasons at max effort" "reasoningEffort: max" escalatorText)
    (infixRow "escalator droid is read-only" "tools: read-only" escalatorText)
    (infixRow "escalator droid registers the jev MCP" "mcpServers: [\"jev\"]" escalatorText)
    (infixRow "escalator droid must not select model tiers" "never use it to select a model tier"
      escalatorText
    )

    # Activation wiring: the merge tool runs after writeBoundary with the
    # managed factory dir and the current jev-mcp store path.
    (row "configureFactory activation exists" (activation != null) "home.activation.configureFactory")
    (row "configureFactory runs after writeBoundary" (
      activationAfter == [ "writeBoundary" ]
    ) "entryAfter [ \"writeBoundary\" ]")
    (row "configureFactory invokes factory-config-merge on the managed factory dir" (
      lib.hasInfix "factory-config-merge" activationData
      && lib.hasInfix "--factory-dir ${factoryDir}" activationData
    ) "factory-config-merge --factory-dir ${factoryDir}")
    (row "configureFactory registers the current jev-mcp store path" (
      lib.hasInfix "--jev-command " activationData && lib.hasPrefix jevCommand jevCommandArg
    ) "--jev-command ${jevCommand}")

    # Jev MCP registration the merge tool writes: stdio transport, the
    # placeholder key (secret supply is the factory-droid launcher's job),
    # and the bounded timeouts.
    (row "merge tool keeps the jev MCP registration" (
      lib.hasInfix "\"type\": \"stdio\"" mergeSource
      && lib.hasInfix "OPENROUTER_API_KEY" mergeSource
      && lib.hasInfix "\${OPENROUTER_JEV_KEY}" mergeSource
      && lib.hasInfix "30_000" mergeSource
      && lib.hasInfix "60_000" mergeSource
    ) "stdio jev entry, OPENROUTER_JEV_KEY placeholder, 30s/60s timeouts")

    # Model routing literals (the merge tool is the single owner).
    (routeRow "parent model" "model" "glm-5.3-flash" "reasoningEffort" "max")
    (routeRow "light subagent" "lightModel" "glm-5.3-flash" "lightReasoningEffort" "high")
    (routeRow "medium subagent" "mediumModel" "glm-5.3-flash" "mediumReasoningEffort" "max")
    (routeRow "heavy subagent" "heavyModel" "glm-5.3" "heavyReasoningEffort" "max")
    (routeRow "spec mode" "specModeModel" "glm-5.3" "specModeReasoningEffort" "max")
    (routeRow "mission workers" "workerModel" "glm-5.3-flash" "workerReasoningEffort" "max")
    (routeRow "mission validation worker" "validationWorkerModel" "glm-5.3"
      "validationWorkerReasoningEffort"
      "max"
    )
    (routeRow "mission orchestrator" "missionOrchestratorModel" "glm-5.3"
      "missionOrchestratorReasoningEffort"
      "max"
    )
    (infixRow "model fallbacks chain glm-5.3-flash to glm-5.3"
      "\"modelFallbacks\": {\"glm-5.3-flash\": \"glm-5.3\"}"
      mergeSource
    )
  ]
  # Portable exposure on aarch64; only evaluable when the checks wiring
  # forwards the package set (asserted below before this list is read).
  ++ lib.optionals (portablePackages != null) (
    map
      (
        name:
        row "portable package set exposes ${name}" (builtins.elem name portableNames)
          "packages.aarch64-linux.${name}"
      )
      [
        "factory-config"
        "factory-droid"
        "jev-mcp"
      ]
  );

  failedRows = builtins.filter (entry: !entry.pass) checks;
in
assert expect (
  portablePackages != null
) "the checks wiring must forward portablePackages to factory-invariants (see checks/default.nix)";
assert expect (failedRows == [ ])
  "Factory invariants failed:\n${
    lib.concatMapStrings (
      entry: "  - ${entry.name}: expected ${entry.expected}, got ${entry.actual}\n"
    ) failedRows
  }";
pkgs.runCommand "factory-invariants-check" { } ''
  mkdir -p "$out"
  printf 'ok\n' > "$out/result"
''
