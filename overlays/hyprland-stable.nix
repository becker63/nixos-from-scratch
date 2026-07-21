{ hyprland-pinned-nixpkgs }:
final: prev:
let
  pinned = import hyprland-pinned-nixpkgs {
    system = prev.stdenv.hostPlatform.system;
    config = prev.config;
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
