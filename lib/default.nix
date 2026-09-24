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
    (import ../overlays/mini-swe-agent.nix {
      inherit (inputs) mini-swe-agent-src;
    })
    (import ../overlays/my-xonsh.nix)
    (import ../overlays/scripts.nix)
    (import ../overlays/alacritty-copy-buffer.nix)
    (
      final: prev:
      let
        # This wrapper is personal, unpublished source.  Keep it as an
        # explicitly optional local override so the flake remains evaluable
        # on machines that do not have this checkout.
        localCodexExtPackage = "/home/becker/projects/codex-ext/nix/package.nix";
        codexExt =
          if builtins.pathExists localCodexExtPackage then
            final.callPackage localCodexExtPackage { codex = prev.codex; }
          else
            prev.codex;
      in
      {
        codex-base = prev.codex;
        codex-ext = codexExt;
        codex = codexExt;
      }
    )
    (import ../overlays/hascard.nix)
    (import ../overlays/buildbuddy.nix)
    (import ../overlays/gdm-path.nix)
    (import ../overlays/hyprland-stable.nix {
      hyprland-pinned-nixpkgs = inputs.hyprland-pinned-nixpkgs;
    })
    (import ../overlays/zed-dual.nix {
      inherit (inputs) zed-preview-bin;
    })
    (import ../overlays/attune-demo-director.nix)
  ];
}
