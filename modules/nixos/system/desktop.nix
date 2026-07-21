{ lib, pkgs, ... }:

{
  programs.hyprland.enable = true;
  programs.sway = {
    enable = true;
    package = pkgs.swayfx;
  };

  xdg.portal = {
    enable = true;
    wlr.enable = lib.mkForce false;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.gdm.enableGnomeKeyring = true;

  services.displayManager.gdm = {
    enable = true;
    debug = true;
  };

  # GDM's media-key daemon handles these keys before logind sees them.
  programs.dconf.profiles.gdm.databases = lib.mkBefore [
    (let
      emptyStringArray = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
    in
    {
      settings = {
        "org/gnome/settings-daemon/plugins/media-keys" = {
          suspend = emptyStringArray;
          suspend-static = emptyStringArray;
          hibernate = emptyStringArray;
          hibernate-static = emptyStringArray;
        };
        "org/gnome/settings-daemon/plugins/power" = {
          power-button-action = "nothing";
        };
      };
      lockAll = true;
    })
  ];

  # GDM's greeter session file lives under share/gnome-session, and GNOME 50's
  # greeter handoff now actively searches the system profile for it.
  environment.pathsToLink = [ "/share/gnome-session" ];

  qt = {
    enable = true;
    platformTheme = "gtk2";
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_SESSION_TYPE = "wayland";
    QT_QPA_PLATFORM = "wayland";
    GDK_BACKEND = "wayland";
    FREETYPE_PROPERTIES = "truetype:interpreter-version=38";
  };

  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
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
    hinting = {
      enable = true;
      style = "slight";
    };
    antialias = true;
    subpixel.rgba = "rgb";
  };
}
