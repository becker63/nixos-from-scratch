{ inputs, ... }:

{
  overlays = [
    inputs.nur-unstable.overlays.default
    (import ../overlays/xontribs-and-pkgs.nix {
      inherit (inputs)
        copier-templates-extensions-src
        xontrib-jedi-src
        xontrib-prompt-starship-src
        ;
    })
    (import ../overlays/my-xonsh.nix)
    (import ../overlays/scripts.nix)
    (final: prev: {
      codex-base = prev.codex;
      codex-ext = final.callPackage (inputs.codex-ext-src + "/nix/package.nix") {
        codex = prev.codex;
      };
      codex = final.codex-ext;
    })
    (import ../overlays/hascard.nix)
    (import ../overlays/buildbuddy.nix)
    (import ../overlays/gdm-path.nix)
    (import ../overlays/hyprland-stable.nix {
      hyprland-pinned-nixpkgs = inputs.hyprland-pinned-nixpkgs;
    })
    (import ../overlays/zed-dual.nix {
      inherit (inputs) zed-preview-bin;
    })
  ];
}
