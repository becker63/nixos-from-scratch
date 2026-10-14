(import ./default.nix {
  nixpkgsSource = builtins.storePath "NIXPKGS_SOURCE_PATH";
  desktopSource = ./config;
  wallpaper = ./wallpaper.jpg;
}).host
