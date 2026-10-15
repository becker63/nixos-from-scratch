{ helper }:
{
  jev-tunnel = {
    Unit = {
      Description = "Native Jev MCP through independent OpenAI Secure MCP Tunnel";
      ConditionPathExists = "%h/.config/tunnel-client/jev.json";
      StartLimitIntervalSec = 120;
      StartLimitBurst = 10;
    };
    Service = {
      ExecStart = "${helper} run";
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
  jev-tunnel-health = {
    Unit = {
      Description = "Independent Jev tunnel readiness and polling check";
      Requisite = "jev-tunnel.service";
      After = "jev-tunnel.service";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${helper} health";
      UMask = "0077";
      NoNewPrivileges = true;
    };
  };
}
