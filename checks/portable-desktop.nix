{ inputs, system }:
let
  lib = inputs.nixpkgs-unstable.lib;
  systemConfig = lib.nixosSystem {
    inherit system;
    modules = [
      inputs.self.nixosModules.desktop
      {
        system.stateVersion = "26.05";
        users.users.becker = {
          isNormalUser = true;
          uid = 1000;
        };
        home-manager.users.becker.becker.desktop.portable = true;
      }
    ];
  };
  c = systemConfig.config;
  h = c.home-manager.users.becker;
  hyprText = h.xdg.configFile.hypr.source.text;
  sources = lib.mapAttrs (_: file: toString file.source) h.xdg.configFile;
  expect = condition: message: lib.assertMsg condition "portable desktop: ${message}";
in
assert expect c.programs.hyprland.enable "Hyprland must be enabled";
assert expect c.xdg.portal.enable "Wayland portals must be enabled";
assert expect (h.home.username == "becker") "the normal user must be preserved";
assert expect h.becker.desktop.portable "portable mode must be enabled";
assert expect (builtins.all (pattern: !(lib.hasInfix pattern hyprText)) [
  "eDP-1"
  "Apple SMC"
  "WLR_DRM_NO_ATOMIC"
  "kb_model = apple"
  "~/nixos-from-scratch"
]) "portable Hyprland must not retain laptop hardware or checkout paths";
assert expect (lib.hasInfix "monitor = , preferred, auto, 1" hyprText)
  "monitors must be detected automatically";
assert expect (builtins.all (lib.hasPrefix "/nix/store/") (
  builtins.attrValues sources
)) "dotfiles must not depend on the live laptop checkout";
assert expect (!c.services.displayManager.gdm.enable) "the consumer chooses its login manager";
assert expect (
  c.boot.kernelPackages.kernel.pname != "linux-asahi"
) "Asahi hardware must not be imported";
assert expect (
  c.users.users.becker.hashedPassword == null
) "password verifiers must not enter the store";
systemConfig.pkgs.writeText "portable-desktop-contract.json" (
  builtins.toJSON {
    inherit system sources;
    user = h.home.username;
    hyprland = c.programs.hyprland.package.version;
    alacritty = systemConfig.pkgs.alacritty.version;
  }
)
