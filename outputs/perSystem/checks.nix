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
      };
    in
    {
      alacritty-copybuffer = checkSuite.alacrittyCopybuffer;
      asahi-gaming = checkSuite.asahiGaming;
      desktop-osd-contract = checkSuite.desktopOsd.check;
      gdm-greeter-preflight = checkSuite.greeter.check;
      home-invariants = checkSuite.homeInvariants.check;
      hyprland-gpu-preflight = checkSuite.hyprlandGpu.check;
      opencode-context-stack-e2e = checkSuite.opencodeContext.check;
      switch-safety = checkSuite.switchSafety.check;
      system-invariants = checkSuite.systemInvariants.check;
      xonsh-config = checkSuite.xonshConfig;
    };

  # x86_64 exposes exactly one light check: an eval-assert guarding the
  # portable package surface (nothing builds; forcing the check's
  # derivation fires the assert chain).
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
  # building anything.
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
  assert expect (portableDrvPaths != [ ]) "the portable packages must evaluate on x86_64-linux";
  assert expect (
    leakedHostBound == [ ]
  ) "host-bound packages must not leak to x86_64-linux: ${lib.concatStringsSep ", " leakedHostBound}";
  {
    portable-packages-eval = pkgs.runCommand "portable-packages-eval" { } ''
      mkdir -p "$out"
      printf 'ok\n' > "$out/result"
    '';
  }
