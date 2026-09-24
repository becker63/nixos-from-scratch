{
  inputs',
  outputs',
  pkgs,
  nodes,
  system,
  ...
}:

let
  inherit (pkgs) lib;

  # aarch64 keeps the full invariant suite. Every check in it is host-bound
  # to the nixos-btw configuration and must be built from the HOST's overlay
  # pkgs (checks assert against overlay packages such as the xonsh wrapper,
  # not upstream's), so the perSystem `pkgs` must not back this branch.
  aarch64Checks =
    let
      checkSuite = import ../../checks {
        pkgs = nodes.nixos-btw.pkgs;
        config = nodes.nixos-btw.config;
        hyprConfigFile = ../../config/hypr/hyprland.conf;
        sourceRoot = ../..;
        portablePackages = outputs'.packages;
      };
    in
    {
      # Owns the alacritty copy-buffer keybind family. LIGHT-BUILD (realizes a small derivation — safe to build).
      alacritty-copybuffer = checkSuite.alacrittyCopybuffer;
      # Owns the gaming-stack family: steam-asahi, muvm, FEX, doctor, kvm group, gaming sysctls. EVAL-ASSERT + LIGHT-BUILD (binary smoke test).
      asahi-gaming = checkSuite.asahiGaming;
      # Owns the desktop OSD (eww/fnott) rendering contract. LIGHT-BUILD (realizes a small derivation — safe to build).
      desktop-osd-contract = checkSuite.desktopOsd.check;
      # Owns the Factory/Droid/Jev wiring family: policy files, activation, routing literals, portable exposure. EVAL-ASSERT (trivial marker derivation).
      factory-invariants = checkSuite.factoryInvariants;
      # Owns the GDM greeter handoff contract on the generated closure. REBUILD-TIME (interpolates config.system.build.toplevel — NEVER build in this mission).
      gdm-greeter-preflight = checkSuite.greeter.check;
      # Owns the Home Manager invariant table + opencode JSON semantics. EVAL-ASSERT table + LIGHT-BUILD (script part).
      home-invariants = checkSuite.homeInvariants.check;
      # Owns the Hyprland GPU environment-variable contract. LIGHT-BUILD (realizes a small derivation — safe to build).
      hyprland-gpu-preflight = checkSuite.hyprlandGpu.check;
      # Owns the opencode context-stack end-to-end contract. LIGHT-BUILD (source-only mode — safe to build).
      opencode-context-stack-e2e = checkSuite.opencodeContext.check;
      # Owns the pre-switch aggregate safety net: asserts every listed check produced its result marker. REBUILD-TIME (interpolates config.system.build.toplevel transitively — NEVER build in this mission).
      switch-safety = checkSuite.switchSafety.check;
      # Owns the core system invariant family: kernel pname, boot chain, firmware, UUIDs, swap tiering, groups, binfmt. EVAL-ASSERT layer + REBUILD-TIME preflight component (interpolates config.system.build.toplevel — NEVER build in this mission).
      system-invariants = checkSuite.systemInvariants.check;
      # Owns the xonsh rc semantics family. LIGHT-BUILD (realizes a small derivation — safe to build).
      xonsh-config = checkSuite.xonshConfig;
    };

  # x86_64 exposes exactly one check: portable-packages-eval, an
  # EVAL-ASSERT guarding the portable package surface (nothing builds;
  # forcing the check's derivation fires the assert chain).
  expect =
    condition: message:
    assert lib.assertMsg condition message;
    true;

  portableNames = builtins.attrNames outputs'.packages;

  # Everything the host-bound branch of packages.nix exports on aarch64 —
  # none of it may appear under x86_64.
  hostBoundNames = [
    "asahi-gaming-check"
    "asahi-gaming-doctor"
    "attune-demo-director"
    "buildbuddy-cli"
    "codex"
    "codex-base"
    "codex-ext"
    "desktop-osd-contract"
    "greeter-preflight"
    "home-invariants"
    "hyprland-gpu-preflight"
    "mini-attune"
    "mini-swe-agent"
    "opencode-context-stack-e2e"
    "steam-asahi"
    "switch-safety"
    "system-invariants"
    "zed"
    "zed-deps-report"
    "zed_raw"
  ];
  leakedHostBound = lib.filter (name: builtins.elem name hostBoundNames) portableNames;

  hasDroid = (inputs'.llm-agents.packages or { }) ? droid;

  # Forcing drvPaths evaluates the portable derivations on x86_64 without
  # building anything. The assert below forces every element through
  # builtins.all — a bare `portableDrvPaths != [ ]` never would, because
  # list disequality short-circuits on length without forcing elements.
  portableDrvPaths = map (name: outputs'.packages.${name}.drvPath) (
    [
      "jev-mcp"
      "factory-config"
    ]
    ++ lib.optionals hasDroid [ "factory-droid" ]
  );
in
if system == "aarch64-linux" then
  aarch64Checks
else
  assert expect (builtins.elem "jev-mcp" portableNames) "jev-mcp must be exposed for x86_64-linux";
  assert expect (builtins.elem "factory-config" portableNames)
    "factory-config must be exposed for x86_64-linux";
  assert expect (
    !hasDroid || builtins.elem "factory-droid" portableNames
  ) "factory-droid must be exposed for x86_64-linux when llm-agents publishes droid for it";
  assert expect (builtins.all (
    d: builtins.isString d
  ) portableDrvPaths) "the portable packages must evaluate on x86_64-linux";
  assert expect (
    leakedHostBound == [ ]
  ) "host-bound packages must not leak to x86_64-linux: ${lib.concatStringsSep ", " leakedHostBound}";
  {
    # Owns the portable-surface family: portable packages exposed on x86_64, nothing host-bound leaks. EVAL-ASSERT (trivial marker derivation).
    portable-packages-eval = pkgs.runCommand "portable-packages-eval" { } ''
      mkdir -p "$out"
      printf 'ok\n' > "$out/result"
    '';
  }
