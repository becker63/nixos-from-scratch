{
  config,
  lib,
  pkgs,
  desktopSource,
  wallpaper,
  nixpkgsSource,
  jovianSource,
  ...
}:
let
  gamingHost = pkgs.writeShellApplication {
    name = "gaming-host-session";
    runtimeInputs = [ config.programs.hyprland.package ];
    text = ''
      exec Hyprland --config /etc/gaming-box/gaming-host.conf
    '';
  };
  nestedStart = pkgs.writeShellApplication {
    name = "gaming-nested-start";
    runtimeInputs = [
      pkgs.gamescope-session
      pkgs.systemd
      pkgs.steamos-manager
      pkgs.jq
      config.programs.hyprland.package
    ];
    text = ''
      # Replace stale desktop values with this gaming compositor's socket.
      read -r GAMESCOPE_HOST_WIDTH GAMESCOPE_HOST_HEIGHT < <(
        hyprctl monitors -j | jq -r '.[0] | "\(.width | floor) \(.height | floor)"'
      )
      export GAMESCOPE_HOST_WIDTH GAMESCOPE_HOST_HEIGHT
      systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE GAMESCOPE_HOST_WIDTH GAMESCOPE_HOST_HEIGHT
      export XDG_CURRENT_DESKTOP=gamescope DESKTOP_SESSION=gamescope-wayland
      status=0
      start-gamescope-session || status=$?
      result="$(systemctl --user show gamescope-session --property=Result --value)"
      if [ "$status" -ne 0 ] || [ "$result" != success ]; then
        # A failed gaming session must return to recovery, never autologin-loop.
        systemctl --user stop steam-launcher.service || true
        steamosctl switch-to-desktop-mode || true
      fi
      hyprctl dispatch exit || true
      exit "$status"
    '';
  };
  mode = pkgs.writeShellApplication {
    name = "gaming-mode";
    runtimeInputs = [
      pkgs.steamos-manager
      config.programs.hyprland.package
      pkgs.alacritty
    ];
    text = ''
      case "''${1:-}" in
        steam)
          steamosctl switch-to-game-mode
          exec hyprctl dispatch exit
          ;;
        terminal) exec alacritty -e bash -l ;;
        *) echo 'Usage: gaming-mode {steam|terminal}; use Steam Switch to Desktop for desktop mode.' >&2; exit 2 ;;
      esac
    '';
  };
  hypr = lib.concatStringsSep "\n" (
    builtins.filter (
      line:
      !(lib.hasPrefix "monitor =" line)
      && !(lib.hasPrefix "env = WLR_DRM_NO_ATOMIC" line)
      && !(lib.hasPrefix "bindl = , switch:" line)
      && !(lib.hasInfix "systemctl --user start eww-osd.service" line)
      && !(lib.hasInfix "Steam client and Steam-launched" line)
      && !(lib.hasPrefix "windowrule = workspace 4 silent" line)
      && !(lib.hasPrefix "env = GDK_DPI_SCALE" line)
      && !(lib.hasPrefix "env = QT_SCALE_FACTOR" line)
      && !(lib.hasPrefix "env = XWAYLAND_DPI" line)
      && !(lib.hasInfix "kb_model = apple" line)
      && !(lib.hasInfix "kb_options =" line)
      && !(lib.hasInfix "pseudotile =" line)
    ) (lib.splitString "\n" (builtins.readFile (desktopSource + "/hypr/hyprland.conf")))
  );
in
{
  imports = [ (jovianSource + "/modules") ];
  # Nested Gamescope uses Hyprland's display and needs no privileged DRM access.
  security.wrappers.gamescope.enable = false;
  jovian = {
    devices.steamdeck.enable = false;
    steam = {
      enable = true;
      autoStart = true;
      user = "becker";
      desktopSession = "hyprland";
      # The legacy boot core aborts in libseat's logind sd-bus dispatch.
      # Use the dedicated seat broker for Gamescope, leaving Hyprland on logind.
      environment.LIBSEAT_BACKEND = "seatd";
      environment.GAMESCOPE_FORCE_GENERAL_QUEUE = "1";
      # The SteamOS WSI layer cannot hook the outer compositor's swapchain.
      environment.ENABLE_GAMESCOPE_WSI = "0";
      # SDL otherwise asks the portal for cursor settings synchronously, while
      # Jovian orders that portal after Gamescope's startup notification.
      environment.XCURSOR_THEME = "breeze_cursors";
      environment.XCURSOR_SIZE = "24";
      # This fullscreen host supplies no client-side window decorations. Avoid
      # libdecor's GTK settings/portal startup while Gamescope is not ready yet.
      environment.SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR = "0";
      environment.SDL_VIDEO_WAYLAND_WMCLASS = "gamescope";
    };
  };
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [
    "kvm-amd"
    "uinput"
  ];
  boot.kernel.sysctl."vm.max_map_count" = 1048576;
  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;
  fileSystems."/" = {
    device = "/dev/disk/by-label/gaming-root";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/GAME_EFI";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };
  services.fstrim.enable = true;
  services.seatd = {
    enable = true;
    # Existing user managers retain their pre-switch supplementary groups.
    # Reuse GPU access membership so migrating doesn't require logging out TTYs.
    group = "video";
  };
  # The nested startup helper imports the current gaming host's Wayland socket.
  # Desktop X11 display values must still stay out of Gamescope's environment.
  systemd.user.services.gamescope-session.serviceConfig.UnsetEnvironment = [
    "DISPLAY"
  ];
  systemd.services.display-manager = {
    requires = [ "seatd.service" ];
    after = [ "seatd.service" ];
  };
  # Keep an independent recovery console available before graphical login.
  systemd.services."getty@tty2".wantedBy = [ "multi-user.target" ];

  networking.hostName = "gaming-box";
  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York";
  nixpkgs.config.allowUnfree = true;
  # Keep Jovian's service lifecycle and SteamOS integration, with Hyprland
  # owning display output to avoid NVIDIA's idle-frame corruption on direct DRM.
  nixpkgs.overlays = lib.mkAfter [
    (_final: prev: {
      gamescope-session = prev.gamescope-session.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          substituteInPlace "$out/share/wayland-sessions/gamescope-wayland.desktop" \
            --replace-fail 'Exec=start-gamescope-session' 'Exec=gaming-host-session'
          # Only the renderer skips session D-Bus. The readiness helper keeps
          # the real bus in gamescope-environment for Steam and its services.
          substituteInPlace "$out/lib/steamos/gamescope-session" \
            --replace-fail 'exec gamescope' \
            'exec ${prev.coreutils}/bin/env DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null gamescope --backend sdl --fullscreen'
          substituteInPlace "$out/lib/steamos/gamescope-session" \
            --replace-fail '-w 1280 -h 800' \
            '-w "''${GAMESCOPE_HOST_WIDTH:-1920}" -h "''${GAMESCOPE_HOST_HEIGHT:-1080}" -W "''${GAMESCOPE_HOST_WIDTH:-1920}" -H "''${GAMESCOPE_HOST_HEIGHT:-1080}"'
          # SDL forwards absolute mouse motion through the touch handler.
          # Passthrough (4) emits touch events without moving Steam's pointer;
          # hover (0) warps the pointer while SDL forwards buttons separately.
          substituteInPlace "$out/lib/steamos/gamescope-session" \
            --replace-fail '--default-touch-mode 4' '--default-touch-mode 0'
        '';
      });
    })
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];
  nix.nixPath = [ "nixpkgs=${nixpkgsSource}" ];
  nix.registry.nixpkgs.to = {
    type = "path";
    path = toString nixpkgsSource;
  };
  programs.nix-ld.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    # Turing (2080 Ti) supports NVIDIA's open kernel module; userspace is proprietary.
    open = true;
    modesetting.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaSettings = true;
    powerManagement.enable = true;
  };
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
    protontricks.enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };
  programs.gamescope.enable = true;
  programs.gamemode.enable = true;
  programs.hyprland.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
  users.users.becker = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "input"
      "gamemode"
      "kvm"
    ];
    # Installed interactively by the installer; no credential goes in the ISO/store.
  };
  users.users.root.hashedPassword = "!";

  environment.systemPackages = with pkgs; [
    gamingHost
    nestedStart
    mode
    (pkgs.writeTextDir "share/applications/return-to-gaming.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=Steam Gaming Mode
      Exec=${lib.getExe mode} steam
      Icon=steam
      Terminal=false
      Categories=Game;
    '')
    alacritty
    tofi
    nautilus
    swaybg
    grim
    slurp
    wl-clipboard
    eww
    brightnessctl
    playerctl
    pavucontrol
    wireplumber
    jq
    ripgrep
    git
    gh
    neovim
    tmux
    htop
    fastfetch
    starship
    atuin
    nodejs
    (pkgs.writeShellScriptBin "charge-status" ''
      printf 'Desktop · external power\n'
    '')
    mangohud
    vulkan-tools
    pciutils
    usbutils
    heroic
    lutris
    wineWow64Packages.stable
    winetricks
    dbus
  ];
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
  };
  programs.bash.interactiveShellInit = ''
    export PATH="$HOME/.npm-global/bin:$PATH"
  '';
  environment.etc."npmrc".text = "prefix=\${HOME}/.npm-global\n";
  systemd.user.services.codex-bootstrap = {
    description = "Install Codex through the user's npm prefix on first login";
    wantedBy = [ "default.target" ];
    unitConfig = {
      ConditionUser = "becker";
      ConditionPathExists = "!%h/.npm-global/bin/codex";
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.nodejs}/bin/npm install --global --prefix %h/.npm-global @openai/codex@0.162.0";
      Restart = "on-failure";
      RestartSec = "60s";
    };
    path = [
      pkgs.nodejs
      pkgs.coreutils
    ];
  };
  systemd.user.services.gaming-dotfiles = {
    description = "Prepare the exported desktop configuration";
    wantedBy = [ "default.target" ];
    before = [ "graphical-session-pre.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ "$USER" = becker ]; then
        mkdir -p "$HOME/.config/hypr" "$HOME/nixos-from-scratch/walls"
        ln -sfn /etc/gaming-box/hyprland.conf "$HOME/.config/hypr/hyprland.conf"
        for name in alacritty tofi starship atuin fastfetch eww; do
          if [ ! -e "$HOME/.config/$name" ] || { [ -L "$HOME/.config/$name" ] && [[ "$(readlink "$HOME/.config/$name")" == /nix/store/* ]]; }; then
            ln -sfn ${desktopSource}/"$name" "$HOME/.config/$name"
          fi
        done
        ln -sfn ${wallpaper} "$HOME/nixos-from-scratch/walls/arnold-bocklin-isle-of-the-dead.jpg"
      fi
    '';
    path = [ pkgs.coreutils ];
  };
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    inter
    noto-fonts
    noto-fonts-color-emoji
  ];
  environment.etc."gaming-box/hyprland.conf".text = hypr + ''

    monitor = , preferred, auto, 1
    input {
      kb_options =
    }
    exec-once = sh -c 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP; eww daemon'
    bind = $mainMod SHIFT, G, exec, gaming-mode steam
    bind = $mainMod SHIFT, T, exec, gaming-mode terminal
  '';
  environment.etc."gaming-box/gaming-host.conf".text = ''
    monitor = , preferred, auto, 1
    input {
      kb_layout = us
      kb_options =
    }
    general {
      gaps_in = 0
      gaps_out = 0
      border_size = 0
    }
    decoration {
      rounding = 0
      blur {
        enabled = false
      }
      shadow {
        enabled = false
      }
    }
    animations {
      enabled = false
    }
    misc {
      disable_hyprland_logo = true
      disable_splash_rendering = true
      background_color = 0x000000
    }
    windowrule {
      name = gamescope-fullscreen
      match:class = gamescope
      fullscreen = on
    }
    exec-once = gaming-nested-start
  '';
  # Opt in on the installed box: services.ollama.enable = true;
  # services.ollama.package = pkgs.ollama-cuda; (models are downloaded separately).
  system.stateVersion = "26.05";
}
