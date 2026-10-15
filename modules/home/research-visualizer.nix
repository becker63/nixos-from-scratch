{ pkgs, ... }:

let
  graphApp = pkgs.callPackage ../../packages/research-workbench/mcp-app { };
in
{
  home.packages = [ graphApp ];

  systemd.user.services.research-visualizer-tunnel = {
    Unit = {
      Description = "Attune research graph Codex App through OpenAI Secure MCP Tunnel";
      ConditionPathExists = "%h/.config/tunnel-client/research-visualizer.yaml";
      StartLimitIntervalSec = 120;
      StartLimitBurst = 10;
    };
    Service = {
      ExecStart = "${graphApp}/bin/research-graph-tunnel run";
      Restart = "always";
      RestartSec = 5;
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      LimitCORE = 0;
      TimeoutStopSec = 15;
      KillMode = "control-group";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
