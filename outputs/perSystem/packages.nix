{
  inputs',
  lib,
  system,
  pkgs,
  nodes,
  ...
}:

let
  # The aarch64 host's overlay-laden pkgs and evaluated configuration. Only
  # the host-bound set may touch these: the portable set must build from the
  # perSystem `pkgs` (plain nixpkgs for this system, overlays absent) so
  # x86_64 consumers are never bound to aarch64-only derivations.
  hostPkgs = nodes.nixos-btw.pkgs;
  hostConfig = nodes.nixos-btw.config;

  # Portable set: pure Python/shell tooling that builds from plain nixpkgs
  # on every system listed in flake.nix.
  portable = {
    jev-mcp = pkgs.callPackage ../../packages/jev-mcp { };
    factory-config = pkgs.callPackage ../../packages/factory-config { };
  }
  // lib.optionalAttrs ((inputs'.llm-agents.packages or { }) ? droid) {
    # factory-droid wraps llm-agents' droid, which is published per system
    # (aarch64 and x86_64 at the locked rev); export it wherever droid
    # exists so a future llm-agents lock change cannot break evaluation.
    factory-droid = pkgs.callPackage ../../packages/factory-droid {
      droid = inputs'.llm-agents.packages.droid;
    };
  };

  # Host-bound set: aarch64-only. These need the host's overlay packages
  # (zed, codex, mini-swe-agent, ...), the host configuration (steam-asahi,
  # asahi-gaming-doctor), or wrap the host-bound check suite.
  hostBound =
    if system == "aarch64-linux" then
      let
        packageName = package: package.pname or (lib.getName package);
        asahi-gaming-doctor =
          lib.findFirst (package: packageName package == "asahi-gaming-doctor")
            (throw "asahi-gaming-doctor is missing from environment.systemPackages")
            hostConfig.environment.systemPackages;
        checkSuite = import ../../checks {
          pkgs = hostPkgs;
          config = hostConfig;
          hyprConfigFile = ../../config/hypr/hyprland.conf;
          sourceRoot = ../..;
          # switch-safety's wrapper interpolates the factory-invariants
          # marker, which fires that check's fail-loud missing-argument
          # assert unless the suite sees the portable set. `portable` above
          # is exactly the portable half of this output.
          portablePackages = portable;
        };
      in
      {
        inherit (hostPkgs)
          attune-demo-director
          buildbuddy-cli
          codex
          codex-base
          codex-ext
          mini-swe-agent
          zed
          zed-deps-report
          ;
        # Same derivation as zed. The rc.xsh `zed_raw` shell alias and
        # zed-deps-report's "nix build .#zed_raw" hint reference this name.
        zed_raw = hostPkgs.zed;
        mini-attune = hostPkgs.callPackage ../../packages/mini-attune { };
        asahi-gaming-check = checkSuite.asahiGaming;
        inherit asahi-gaming-doctor;
        desktop-osd-contract = checkSuite.desktopOsd.package;
        greeter-preflight = checkSuite.greeter.package;
        home-invariants = checkSuite.homeInvariants.package;
        hyprland-gpu-preflight = checkSuite.hyprlandGpu.package;
        opencode-context-stack-e2e = checkSuite.opencodeContext.package;
        switch-safety = checkSuite.switchSafety.package;
        system-invariants = checkSuite.systemInvariants.package;
        steam-asahi = hostConfig.programs.steam-asahi.package;
      }
    else
      { };
in
portable // hostBound
