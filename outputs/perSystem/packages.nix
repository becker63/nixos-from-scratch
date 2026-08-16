{
  nodes,
  ...
}:

let
  inherit (nodes.nixos-btw) pkgs;
  miniAttuneConfig = pkgs.writeText "mini-attune.yaml" (builtins.readFile ../../config/minisweagent/attune.yaml);
  mini-attune = pkgs.writeShellApplication {
    name = "mini-attune";
    runtimeInputs = [
      pkgs.mini-swe-agent
      pkgs.xonsh
    ];
    text = ''
      # mini's setup wizard is global-state based, even with an explicit
      # config. This launcher is fully configured below, so bypass it.
      export MSWEA_CONFIGURED=true
      export MSWEA_SILENT_STARTUP=1
      export MSWEA_ATTUNE_CONVENTIONS=1

      if [ ! -f SPEC.md ]; then
        echo "mini-attune: SPEC.md is required at the project root" >&2
        exit 2
      fi

      if [ -f .env ]; then
        set -a
        # shellcheck source=/dev/null
        . ./.env
        set +a
      fi

      if [ -z "''${OPENROUTER_API_KEY:-}" ]; then
        echo "mini-attune: add OPENROUTER_API_KEY=... to this project's .env" >&2
        exit 2
      fi

      exec mini --yolo --exit-immediately --config '${miniAttuneConfig}' "$@"
    '';
  };
  checkSuite = import ../../checks {
    inherit pkgs;
    config = nodes.nixos-btw.config;
    hyprConfigFile = ../../config/hypr/hyprland.conf;
    sourceRoot = ../..;
  };
in
{
  inherit (pkgs)
    attune-demo-director
    buildbuddy-cli
    codex
    codex-base
    codex-ext
    mini-swe-agent
    zed
    zed-deps-report
    zed_raw
    ;
  inherit mini-attune;
  desktop-osd-contract = checkSuite.desktopOsd.package;
  greeter-preflight = checkSuite.greeter.package;
  home-invariants = checkSuite.homeInvariants.package;
  hyprland-gpu-preflight = checkSuite.hyprlandGpu.package;
  opencode-context-stack-e2e = checkSuite.opencodeContext.package;
  switch-safety = checkSuite.switchSafety.package;
  system-invariants = checkSuite.systemInvariants.package;
}
