{ package }:
{
  buildbuddy-history-tunnel = {
    Unit = {
      Description = "Read-only BuildBuddy history through independent Secure MCP Tunnel";
      ConditionPathExists = "%h/.config/tunnel-client/buildbuddy-history.json";
      StartLimitIntervalSec = 120;
      StartLimitBurst = 10;
    };
    Service = {
      ExecStart = "${package}/bin/buildbuddy-history-tunnel run";
      Restart = "always";
      RestartSec = 5;
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      LimitCORE = 0;
    };
    Install.WantedBy = [ "default.target" ];
  };
  buildbuddy-history-health = {
    Unit = {
      Description = "Independent BuildBuddy history tunnel health";
      Requisite = "buildbuddy-history-tunnel.service";
      After = "buildbuddy-history-tunnel.service";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${package}/bin/buildbuddy-history-tunnel health";
      UMask = "0077";
    };
  };
}
