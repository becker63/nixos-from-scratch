{
  nodes,
  ...
}:

let
  inherit (nodes.nixos-btw) pkgs;
  checkSuite = import ../../checks {
    inherit pkgs;
    config = nodes.nixos-btw.config;
    hyprConfigFile = ../../config/hypr/hyprland.conf;
    sourceRoot = ../..;
  };
in
{
  inherit (pkgs)
    buildbuddy-cli
    codex
    codex-base
    codex-ext
    zed
    zed-deps-report
    zed_raw
    ;
  desktop-osd-contract = checkSuite.desktopOsd.package;
  greeter-preflight = checkSuite.greeter.package;
  home-invariants = checkSuite.homeInvariants.package;
  hyprland-gpu-preflight = checkSuite.hyprlandGpu.package;
  opencode-context-stack-e2e = checkSuite.opencodeContext.package;
  switch-safety = checkSuite.switchSafety.package;
  system-invariants = checkSuite.systemInvariants.package;
}
