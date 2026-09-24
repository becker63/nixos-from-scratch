{
  config,
  pkgs,
  ...
}:

let
  nixStoreGcScript = pkgs.writeShellScript "nix-store-gc" ''
    #!/usr/bin/env bash
    set -euo pipefail

    ${pkgs.nix}/bin/nix-collect-garbage -d
  '';
in
{
  services.logind.settings.Login = {
    HandleSuspendKey = "ignore";
    HandleSuspendKeyLongPress = "ignore";
    HandleHibernateKey = "ignore";
    HandleHibernateKeyLongPress = "ignore";
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    LidSwitchIgnoreInhibited = "yes";
  };

  services.devmon.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.dbus.enable = true;

  systemd.services."nix-store-gc" = {
    description = "Garbage-collect unused Nix store paths";
    serviceConfig.Type = "oneshot";
    script = "${nixStoreGcScript}";
  };

  systemd.timers."nix-store-gc" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 03:00:00"; # weekly, 3am on Sundays
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  systemd.services.systemd-logind.restartTriggers = [
    config.environment.etc."systemd/logind.conf".source
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true; # required for pavucontrol
    jack.enable = false;
    wireplumber.enable = true;
  };

  services.blueman.enable = true;
  services.tailscale.enable = true;

  systemd.user.services.pavucontrol = {
    description = "PulseAudio Volume Control";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.pavucontrol}/bin/pavucontrol";
      Restart = "on-failure";
    };
  };

  services.openssh.enable = true;
}
