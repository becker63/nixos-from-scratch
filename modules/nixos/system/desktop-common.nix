{ lib, pkgs, ... }:

{
  programs.hyprland.enable = true;
  xdg.portal = {
    enable = true;
    wlr.enable = lib.mkForce false;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
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
  # defaultFonts may only name fonts that are actually installed or
  # requested by name somewhere; the never-installed SF Pro Display /
  # SF Pro Text / SF Mono aliases fell through to the next entry anyway.
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      sansSerif = [
        "Inter"
        "Cantarell"
      ];
      serif = [ "Noto Serif" ];
      monospace = [ "JetBrains Mono" ];
    };
    hinting = {
      enable = true;
      style = "slight";
    };
    antialias = true;
    subpixel.rgba = "rgb";
  };
}
