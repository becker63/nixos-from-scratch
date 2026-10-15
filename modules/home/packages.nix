{ pkgs, ... }:

let
  dsh = pkgs.callPackage ../../packages/dsh { };
  chatgpt-desktop = pkgs.callPackage ../../packages/chatgpt-desktop { };
  tunnel-client = pkgs.callPackage ../../packages/tunnel-client { };
  buildbuddy-history = pkgs.callPackage ../../packages/buildbuddy-history { };
  jev-tunnel = pkgs.callPackage ../../packages/jev-mcp/tunnel.nix { };
in
{
  systemd.user.services =
    (import ../../packages/jev-mcp/services.nix {
      helper = "${jev-tunnel}/bin/jev-tunnel";
    })
    // (import ../../packages/buildbuddy-history/services.nix { package = buildbuddy-history; })
    // {
      buildbuddy-tunnel = {
        Unit = {
          Description = "BuildBuddy MCP through OpenAI Secure MCP Tunnel";
          ConditionPathExists = "%h/.config/tunnel-client/buildbuddy.yaml";
        };
        Service = {
          ExecStart = "${tunnel-client}/bin/tunnel-client run --profile-file %h/.config/tunnel-client/buildbuddy.yaml";
          Restart = "on-failure";
          RestartSec = 5;
          UMask = "0077";
          NoNewPrivileges = true;
        };
        Install.WantedBy = [ "default.target" ];
      };

    };
  systemd.user.timers.jev-tunnel-health = jev-tunnel.timer;

  systemd.user.timers.buildbuddy-history-health = buildbuddy-history.timer;

  home.packages = with pkgs; [
    dsh
    buildbuddy-history
    jev-tunnel
    chatgpt-desktop
    tunnel-client
    # Bundle Widevine CDM so DRM-protected streaming works on aarch64.
    (chromium.override { enableWideVine = true; })
    firefox
    (mpv.override {
      scripts = [ ];
      youtubeSupport = false;
    })
    pom
    zed
    scripts
    ripgrep
    nixd
    nixfmt
    rtk
    nodejs
    gcc
    xwallpaper
    virt-viewer
    eww
    swaybg
    bottom
    tofi
    alacritty
    attune-demo-director
    patchelf
    gnumake
    hyprpicker
    uv
    brightnessctl
    pkgs.haskellPackages.hascard
    obsidian
    gh
    evince
    repomix

    atuin

    pnpm
    kiro-cli
    # Kiro desktop/FHS is not available for aarch64-linux yet because
    # upstream does not publish a Linux ARM IDE artifact.
    # kiro-fhs

    # cloc is deliberately absent: the xonsh login shell aliases cloc to tokei
    # (config/xonsh/rc.xsh), so the real binary never resolves in interactive use.
    tokei
    scc

    exercism

    nix-output-monitor

    popsicle

    zoxide
    fd
    fzf
    eza
    television
    spotify-player
    protobuf_29
    moonlight-qt

    obs-studio
    codeql
    bun

    mosh
    code-cursor-fhs
  ];
}
