{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.becker.desktop;
  files = import ../../lib/desktop-files.nix;
  # Transform the actual laptop config, keeping one owner for appearance and
  # keybindings. Only laptop display/device assumptions are removed.
  laptopConfig = builtins.readFile ../../config/hypr/hyprland.conf;
  hardwareLine =
    line:
    builtins.any (prefix: lib.hasPrefix prefix (lib.trim line)) [
      "monitor ="
      "env = WLR_DRM_NO_ATOMIC,"
      "env = GDK_SCALE,"
      "env = GDK_DPI_SCALE,"
      "env = QT_AUTO_SCREEN_SCALE_FACTOR,"
      "env = QT_SCALE_FACTOR,"
      "env = XWAYLAND_DPI,"
      "kb_model = apple"
      "bindl = , switch:on:Apple SMC"
      "bindl = , switch:off:Apple SMC"
      "bindl = , XF86LaunchA,"
    ];
  portableConfig =
    lib.replaceStrings
      [ "~/nixos-from-scratch/walls/arnold-bocklin-isle-of-the-dead.jpg" ]
      [ "${../../walls/arnold-bocklin-isle-of-the-dead.jpg}" ]
      (
        lib.concatStringsSep "\n" (
          builtins.filter (line: !hardwareLine line) (lib.splitString "\n" laptopConfig)
        )
      );
  hypr = pkgs.writeTextDir "hyprland.conf" (
    "monitor = , preferred, auto, 1\n" + portableConfig + "\n" + cfg.extraHyprlandConfig
  );
in
{
  imports = [
    ./base.nix
    ./desktop.nix
  ];
  options.becker.desktop = {
    portable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use store-backed dotfiles and hardware-neutral monitor defaults.";
    };
    extraHyprlandConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Consumer session additions to the shared Hyprland configuration.";
    };
  };
  config = lib.mkIf cfg.portable {
    xdg.configFile = lib.mapAttrs (name: subpath: {
      source = lib.mkForce (if name == "hypr" then hypr else ../../config + "/${subpath}");
    }) files;
    home.packages = with pkgs; [
      alacritty
      zed-editor
      eww
      swaybg
      tofi
      grim
      slurp
      wl-clipboard
      brightnessctl
      playerctl
      nautilus
      jq
    ];
  };
}
