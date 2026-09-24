{ pkgs, ... }:

{
  home.packages = with pkgs; [
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
    #gleam
    erlang

    nix-output-monitor

    # Iso writer tool, provides cli at popsicle
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
    jj
  ];
}
