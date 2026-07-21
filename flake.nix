{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixverse = {
      url = "github:hgl/nixverse/129f0649abeba9df041dc75a6e7b8f70d78b5bd0";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    home-manager-unstable = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    apple-silicon-unstable = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nur-unstable = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Official Zed Preview tarball for aarch64 Linux.
    zed-preview-bin = {
      url = "https://zed.dev/api/releases/preview/latest/zed-linux-aarch64.tar.gz";
      flake = false;
    };

    # Hyprland stays on the known-good package set for this Asahi system.
    hyprland-pinned-nixpkgs.url =
      "github:NixOS/nixpkgs/b12141ef619e0a9c1c84dc8c684040326f27cdcc";

    xontrib-jedi-src = {
      url = "github:xonsh/xontrib-jedi";
      flake = false;
    };
    xontrib-prompt-starship-src = {
      url = "github:anki-code/xontrib-prompt-starship";
      flake = false;
    };
    codex-ext-src = {
      url = "path:/home/becker/projects/codex-ext";
      flake = false;
    };
    copier-templates-extensions-src = {
      url = "github:copier-org/copier-templates-extensions";
      flake = false;
    };
  };

  outputs =
    inputs@{ nixverse, ... }:
    let
      # Nixverse probes optional directories with pathExists. Passing the
      # already-realized flake store path without its source-copy context
      # avoids a cold `nix flake check` trying to inspect a deferred copy.
      flakePath = builtins.unsafeDiscardStringContext (toString ./.);
    in
    nixverse.lib.load {
      inherit inputs flakePath;
      systems = [ "aarch64-linux" ];
    };
}
