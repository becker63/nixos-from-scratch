{
  config,
  lib,
  pkgs,
  ...
}:

let
  xonshPrewarmed = pkgs.writeShellScriptBin "xonsh-prewarmed" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Launch xonsh from the exact Nix store path to ensure we always
    # run the pinned build (not whatever happens to be on $PATH).
    # Add a marker (-DXONSH_PREWARMED=1) so scripts/config can detect
    # this special prewarmed instance.
    xonsh_run=("${pkgs.xonsh}/bin/xonsh" "-DXONSH_PREWARMED=1")
    sess_name="xonsh_$(date +%s)_$$"

    # Ensure 5 reserves exist
    for i in $(seq 1 5); do
      if ! tmux has-session -t "xonsh_reserve_$i" 2>/dev/null; then
        tmux new-session -s "xonsh_reserve_$i" -d "''${xonsh_run[@]}"
      fi
    done

    # Grab the first available reserve
    for i in $(seq 1 5); do
      if tmux rename-session -t "xonsh_reserve_$i" "$sess_name" 2>/dev/null; then
        tmux new-session -s "xonsh_reserve_$i" -d "''${xonsh_run[@]}" || true
        exec tmux attach-session -t "$sess_name"
      fi
    done

    echo "No reserve available!" >&2
    exit 1
  '';
in
{
  imports = [ ./hardware-configuration.nix ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = false;
  };

  boot.kernelModules = [
    "uhid"
    "hidp"
  ];

  networking.hostName = "nixos-btw";
  networking.wireless.iwd = {
    enable = true;
    settings.Network.EnableNetworkConfiguration = true;
  };
  services.resolved.enable = true;
  networking.useNetworkd = false;

  services.tzupdate.enable = false;

  programs.hyprland.enable = true;
  xdg.portal.enable = true;
  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-gtk
    xdg-desktop-portal-wlr
  ];
  programs.nix-ld.enable = true;

  services.gnome.gnome-keyring.enable = true;

  # Required for unlocking keyring on login
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.gdm.enableGnomeKeyring = true;

  users.users.becker = {
    isNormalUser = true;
    password = "jidw";
    extraGroups = [
      "input"
      "video"
      "podman"
      "docker"
      "wheel"
      "storage"
    ];
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
    ];

    shell = "${pkgs.xonsh}/bin/xonsh";
  };

  programs.ssh.knownHosts = {
    nixos-builder = {
      hostNames = [ "192.168.0.102" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILLhQQV3uPgklRz5KZohKyGl1h6VMLbxPOqHF6cCtWzF";
    };
  };

  nix = {
    distributedBuilds = true;

    buildMachines = [
      # Entry for x86_64-linux jobs
      {
        hostName = "192.168.0.102";
        system = "x86_64-linux";
        sshUser = "root";
        sshKey = "/home/becker/.ssh/colmena";
        maxJobs = 6;
        speedFactor = 1;
        supportedFeatures = [
          "kvm"
          "big-parallel"
          "nixos-test"
        ];
      }
      {
        hostName = "192.168.0.102";
        system = "i686-linux";
        sshUser = "root";
        sshKey = "/home/becker/.ssh/colmena";
        maxJobs = 4;
        speedFactor = 1;
        supportedFeatures = [
          "kvm"
          "big-parallel"
          "nixos-test"
        ];
      }
    ];

    settings = {
      #max-jobs = 0;
      builders-use-substitutes = true;
      require-sigs = false;
      #substituters = [
      #  "http://192.168.0.102:5000"
      #  "https://cache.nixos.org"
      #];
      #trusted-substituters = [ "http://192.168.0.102:5000" ];
    };
  };

  users.users.root = {
    initialPassword = "jidw";
  };

  fonts.packages = with pkgs; [ nerd-fonts.jetbrains-mono ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.keep-outputs = true;
  nix.settings.keep-derivations = true;

  nix.settings = {
    extra-substituters = [
      "https://nixos-apple-silicon.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
    ];
  };

  nixpkgs.config.allowUnfree = true;

  programs.sway = {
    enable = true;
    package = pkgs.swayfx;
  };

  services.xserver.displayManager.gdm = {
    enable = true;
    wayland = true;
    debug = true;
  };
  services.lorri.enable = true;

  environment.systemPackages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.zed-mono
    codex
    lorri
    fastfetch
    antigravity-fhs
    wget
    git
    iproute2
    mesa-demos
    nh
    buildah
    killall
    file
    distrobox
    distrobox-tui
    boxbuddy
    xonsh
    tree
    starship
    unzip
    nix-direnv
    pavucontrol
    gnome-keyring
    opencode

    grim
    slurp
    wl-clipboard

    qt6.qtwayland
    qt5.qtwayland

    (writeShellScriptBin "screenshot" ''
      #!/usr/bin/env bash

      mkdir -p "$HOME/Pictures"
      FILE="$HOME/Pictures/$(date +'%Y-%m-%d_%H-%M-%S').png"

      CHOICE=$(printf "Fullscreen\nRegion\nRegion → Clipboard\n" | tofi)

      case "$CHOICE" in
        "Fullscreen")
          grim "$FILE"
          ;;
        "Region")
          grim -g "$(slurp)" "$FILE"
          ;;
        "Region → Clipboard")
          grim -g "$(slurp)" - | wl-copy
          ;;
      esac
    '')

    (writeShellScriptBin "moonlight-asahi" ''
      # Wayland + Asahi GPU environment
      export QT_QPA_PLATFORM=wayland-egl
      export QT_QPA_PLATFORMTHEME=qt5ct
      export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
      export MOZ_ENABLE_WAYLAND=1
      export NIXOS_OZONE_WL=1
      export MESA_LOADER_DRIVER_OVERRIDE=asahi
      export LIBVA_DRIVER_NAME=asahi
      export VDPAU_DRIVER=va_gl
      export XDG_SESSION_TYPE=wayland
      export GDK_BACKEND=wayland

      # Fix Moonlight audio on Asahi / PipeWire
      export SDL_AUDIODRIVER=pulseaudio

      DEFAULT_FLAGS=(
        --no-audio-on-host
        --audio-config stereo
      )

      # If no action supplied, start GUI normally
      if [ $# -eq 0 ]; then
        exec ${pkgs.moonlight-qt}/bin/moonlight "''${DEFAULT_FLAGS[@]}"
      else
        exec ${pkgs.moonlight-qt}/bin/moonlight "''${DEFAULT_FLAGS[@]}" "$@"
      fi
    '')

    scripts
    wgetpaste
    bat

    bluez
    bluez-tools
    blueman
    bluetuith

    tailscale
  ];

  qt = {
    enable = true;
    platformTheme = "gtk2";
  };

  services.devmon.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  environment.shells = [ "${pkgs.xonsh}/bin/xonsh" ];

  environment.etc."distrobox/distrobox.conf".text = ''
    container_additional_volumes="/nix/store:/nix/store:ro /etc/profiles/per-user:/etc/profiles/per-user:ro /etc/static/profiles/per-user:/etc/static/profiles/per-user:ro"
  '';

  networking.firewall.allowPing = true;

  virtualisation.podman = {
    enable = false;
    dockerCompat = true;
  };

  virtualisation.docker = {
    enable = true;
  };

  systemd.user.services."tmux-prune" = {
    description = "Prune detached tmux sessions";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.scripts}/bin/tmux_prune";
      Environment = [ "PATH=${pkgs.tmux}/bin:/run/current-system/sw/bin:/usr/bin" ];
    };
  };

  systemd.user.timers."tmux-prune" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5"; # every 5 minutes
      Persistent = true; # catch up if the machine was off
    };
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_SESSION_TYPE = "wayland";
    QT_QPA_PLATFORM = "wayland";
    GDK_BACKEND = "wayland";
    FREETYPE_PROPERTIES = "truetype:interpreter-version=38";

  };

  services.dbus.enable = true;

  fonts.fontconfig.enable = true;
  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "Inter"
      "SF Pro Display"
      "Cantarell"
    ];
    serif = [
      "SF Pro Text"
      "Noto Serif"
    ];
    monospace = [
      "JetBrains Mono"
      "SF Mono"
    ];
  };

  fonts.fontconfig.hinting.enable = true;
  fonts.fontconfig.hinting.style = "slight";
  fonts.fontconfig.antialias = true;
  fonts.fontconfig.subpixel.rgba = "rgb";

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

  services.tailscale = {
    enable = false;
    #openFirewall = true;
    #extraUpFlags = [
    #  "--accept-routes=true"
    #  "--accept-dns=false"
    #];
  };

  systemd.user.services.pavucontrol = {
    description = "PulseAudio Volume Control";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.pavucontrol}/bin/pavucontrol";
      Restart = "on-failure";
    };
  };

  system.stateVersion = "25.05";
}
