{ outputs', ... }:

{
  attune-demo-director = {
    type = "app";
    program = "${outputs'.packages.attune-demo-director}/bin/attune-demo-director";
  };
  zed-deps-report = {
    type = "app";
    program = "${outputs'.packages.zed-deps-report}/bin/zed-deps-report";
  };
  greeter-preflight = {
    type = "app";
    program = "${outputs'.packages.greeter-preflight}/bin/gdm-greeter-preflight";
  };
  hyprland-gpu-preflight = {
    type = "app";
    program = "${outputs'.packages.hyprland-gpu-preflight}/bin/hyprland-gpu-preflight";
  };
  opencode-context-stack-e2e = {
    type = "app";
    program = "${outputs'.packages.opencode-context-stack-e2e}/bin/opencode-context-stack-e2e";
  };
  desktop-osd-contract = {
    type = "app";
    program = "${outputs'.packages.desktop-osd-contract}/bin/desktop-osd-contract";
  };
  home-invariants = {
    type = "app";
    program = "${outputs'.packages.home-invariants}/bin/home-invariants";
  };
  switch-safety = {
    type = "app";
    program = "${outputs'.packages.switch-safety}/bin/switch-safety";
  };
  system-invariants = {
    type = "app";
    program = "${outputs'.packages.system-invariants}/bin/system-invariants-preflight";
  };
}
