{ pkgs, ... }:

{
  systemd.user.services.eww-osd = {
    Unit = {
      Description = "Minimal volume and power overlays";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.eww}/bin/eww daemon --no-daemonize";
      ExecStartPost = "${pkgs.writeShellScript "eww-power-hotspot-start" ''
        for attempt in {1..100}; do
          if ${pkgs.eww}/bin/eww ping >/dev/null 2>&1; then
            exec ${pkgs.eww}/bin/eww open power_hotspot
          fi
          ${pkgs.coreutils}/bin/sleep 0.05
        done
        exit 1
      ''}";
      ExecReload = "${pkgs.eww}/bin/eww reload";
      Restart = "on-failure";
      RestartSec = 1;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
