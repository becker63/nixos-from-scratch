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
  # Hyprland imports its display into the persistent user manager. Gamescope
  # must start on DRM rather than trying to nest inside the departed desktop.
  systemd.user.services.gamescope-session.serviceConfig.UnsetEnvironment = [
    "WAYLAND_DISPLAY"
    "DISPLAY"
    "HYPRLAND_INSTANCE_SIGNATURE"
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
  # Jovian's session launcher references pkgs.steam directly. Apply the UI
  # workaround after its overlay so desktop and gaming launchers both use it.
  nixpkgs.overlays = lib.mkAfter [
    (_final: prev: {
      steam = prev.steam.override {
        extraArgs = "-cef-disable-gpu -cef-disable-gpu-compositing";
      };
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
  # Opt in on the installed box: services.ollama.enable = true;
  # services.ollama.package = pkgs.ollama-cuda; (models are downloaded separately).
  system.stateVersion = "26.05";
}
