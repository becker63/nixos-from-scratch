{ pkgs, ... }:

let
  # Standalone script packages (packages/<name>), extracted from this file so
  # it stays a plain package list. charge-monitor gets charge-status passed
  # explicitly because the latter is defined here, not in nixpkgs.
  charge-status = pkgs.callPackage ../../../packages/charge-status { };
  charge-monitor = pkgs.callPackage ../../../packages/charge-monitor { inherit charge-status; };
  screenshot = pkgs.callPackage ../../../packages/screenshot { };
  moonlight-asahi = pkgs.callPackage ../../../packages/moonlight-asahi { };

  # Shared mini-attune definition (packages/mini-attune); it needs this
  # host's overlay pkgs for mini-swe-agent and xonsh.
  miniAttune = pkgs.callPackage ../../../packages/mini-attune { };
in
{
  environment.systemPackages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.zed-mono
    mini-swe-agent
    miniAttune
    fastfetch
    charge-status
    charge-monitor
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
    yek
    tree
    starship
    unzip
    direnv
    nix-direnv
    pavucontrol
    gnome-keyring

    # Kept in the system layer: the HM layer's copies are being removed by the
    # home-manager-cleanup feature, and the screenshot script needs them on
    # PATH wherever it is invoked from.
    grim
    slurp
    wl-clipboard

    qt6.qtwayland
    qt5.qtwayland
    gdm
    gnome-session
    gnome-shell

    screenshot

    moonlight-asahi

    bat

    bluez
    bluez-tools
    blueman
    bluetuith

    ncdu
    tailscale
    age
    ssh-to-age
    sops
    jq
    nmap
    arp-scan
    usbutils
    gptfdisk
    parted
    pv
    nixos-anywhere
    nautilus
  ];
}
