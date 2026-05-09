{
  config,
  pkgs,
  lib,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/nixos-from-scratch/config";
  create_symlink = path: config.lib.file.mkOutOfStoreSymlink path;

  configs = {
    hypr = "hypr";
    waybar = "waybar";
    nvim = "nvim";
    wofi = "wofi";
    alacritty = "alacritty";
    xonsh = "xonsh";
    tofi = "tofi";
    tmux = "tmux";
    starship = "starship";
    zed = "zed";
    sway = "sway";
    atuin = "atuin";
  };

in
{
  home.sessionPath = [ "${config.home.homeDirectory}/.npm-global/bin" ];

  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';

  home.file.".pi/agent/extensions/Agent-Tldr-Munger".source =
    create_symlink "${dotfiles}/pi/extensions/Agent-Tldr-Munger";

  home.file.".pi/agent/settings.json".source = create_symlink "${dotfiles}/pi/settings.json";

  home.file.".pi/agent/auth.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.secrets/pi/auth.json";

  home.activation.installPiCodingAgent = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export HOME="${config.home.homeDirectory}"
    export NPM_CONFIG_PREFIX="${config.home.homeDirectory}/.npm-global"
    export PATH="${
      lib.makeBinPath [
        pkgs.nodejs
        pkgs.gnugrep
        pkgs.coreutils
      ]
    }:$PATH"

    mkdir -p "${config.home.homeDirectory}/.npm-global"

    wanted='@mariozechner/pi-coding-agent@0.62.0'

    if ! npm list -g --depth=0 2>/dev/null | grep -q "$wanted"; then
      npm install -g "$wanted"
    fi
  '';

  home.username = "becker";
  home.homeDirectory = "/home/becker";
  home.stateVersion = "25.05";
  # Home manager doesnt have 25.11 yet
  home.enableNixpkgsReleaseCheck = false;

  programs.git = {
    enable = true;

    userName = "becker63";
    userEmail = "johnsontaylor6320@gmail.com";

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      credential.helper = "!gh auth git-credential";
    };
  };

  programs.bash = {
    enable = true;
    initExtra = ''
      # Function to get active Hyprland workspace
      get_workspace() {
        if command -v hyprctl >/dev/null 2>&1; then
          hyprctl monitors -j 2>/dev/null \
            | jq -r '.[0].activeWorkspace.name' \
            || echo "?"
        else
          echo "tty"
        fi
      }

      # PS1 with username, cwd, and workspace
      export PS1="\\[\\e[38;5;75m\\]\\u@\\h \\[\\e[38;5;113m\\]\\w \\[\\e[38;5;189m\\][WS:\$(get_workspace)]\\$ \\[\\e[0m\\]"
    '';
  };

  # Symlink dotfiles into ~/.config
  xdg.configFile = builtins.mapAttrs (name: subpath: {
    source = create_symlink "${dotfiles}/${subpath}";
    recursive = true;
  }) configs;

  programs.atuin = {
    enable = true;
    daemon = {
      enable = false;
    };
  };

  home.packages = with pkgs; [
    vscode-fhs
    neovim
    chromium
    firefox
    pom
    zed
    ripgrep
    nixd
    nixfmt
    nodejs
    gcc
    xwallpaper
    virt-viewer
    waybar
    swaybg
    grim
    slurp
    wl-clipboard
    jq
    bottom
    arttime
    tofi
    kitty
    alacritty
    tmux
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

    nodejs
    pnpm

    tokei

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
    tmuxp
    protobuf_29
    cloc
    moonlight-qt

    obs-studio
    codeql
    paseo
    paseo-desktop
    bun

    mosh
    tmux

    code-cursor-fhs
  ];
}
