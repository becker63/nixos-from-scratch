{ config, ... }:

let
  dotfiles = "${config.home.homeDirectory}/nixos-from-scratch/config";
  create_symlink = path: config.lib.file.mkOutOfStoreSymlink path;

  configs = {
    hypr = "hypr";
    alacritty = "alacritty";
    xonsh = "xonsh";
    tofi = "tofi";
    starship = "starship";
    zed = "zed";
    sway = "sway";
    atuin = "atuin";
    fastfetch = "fastfetch";
    eww = "eww";
  };
in
{
  home.username = "becker";
  home.homeDirectory = "/home/becker";
  home.stateVersion = "25.05";
  # Keep this off because the system follows unstable inputs rather than a
  # matching Home Manager release check.
  home.enableNixpkgsReleaseCheck = false;

  programs.git = {
    enable = true;

    settings = {
      user.name = "becker63";
      user.email = "johnsontaylor6320@gmail.com";
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

  # Symlink dotfiles into ~/.config.
  xdg.configFile = builtins.mapAttrs (_name: subpath: {
    source = create_symlink "${dotfiles}/${subpath}";
    recursive = true;
  }) configs;

  programs.atuin = {
    enable = true;
    daemon = {
      enable = false;
    };
  };
}
