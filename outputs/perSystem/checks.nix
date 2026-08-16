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
  alacritty-copybuffer = checkSuite.alacrittyCopybuffer;
  desktop-osd-contract = checkSuite.desktopOsd.check;
  gdm-greeter-preflight = checkSuite.greeter.check;
  home-invariants = checkSuite.homeInvariants.check;
  hyprland-gpu-preflight = checkSuite.hyprlandGpu.check;
  opencode-context-stack-e2e = checkSuite.opencodeContext.check;
  switch-safety = checkSuite.switchSafety.check;
  system-invariants = checkSuite.systemInvariants.check;
  xonsh-config = checkSuite.xonshConfig;
}
