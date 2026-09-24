{ hyprland-pinned-nixpkgs }:
final: prev:
let
  pinned = import hyprland-pinned-nixpkgs {
    system = prev.stdenv.hostPlatform.system;
    # This intentionally older package set predates the current nullable
    # `nixpkgs.config.rewriteURL`.  Its fetchurl implementation expects an
    # actual URL-rewriting function, so preserve the current URLs explicitly.
    config = prev.config // {
      rewriteURL = url: url;
    };
  };
in
{
  aquamarine = pinned.aquamarine;
  hyprcursor = pinned.hyprcursor;
  hyprgraphics = pinned.hyprgraphics;
  hypridle = pinned.hypridle;
  hyprland = pinned.hyprland;
  hyprland-qtutils = pinned.hyprland-qtutils;
  hyprlang = pinned.hyprlang;
  hyprlock = pinned.hyprlock;
  hyprpaper = pinned.hyprpaper;
  hyprpicker = pinned.hyprpicker;
  hyprpolkitagent = pinned.hyprpolkitagent;
  hyprutils = pinned.hyprutils;
  hyprwayland-scanner = pinned.hyprwayland-scanner;
  xdg-desktop-portal-hyprland = pinned.xdg-desktop-portal-hyprland;
}
