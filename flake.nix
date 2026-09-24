{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixverse = {
      url = "github:hgl/nixverse/129f0649abeba9df041dc75a6e7b8f70d78b5bd0";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.nixos-anywhere.follows = "nixos-anywhere";
    };

    # Keep Nixverse's deployment app compatible with the current Nixpkgs
    # system matrix instead of inheriting its older transitive lock.
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
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

    # Nixpkgs provides muvm/FEX/libkrun, but not yet the NixOS-specific
    # Steam/PressureVessel launcher needed on 16 KiB-page Apple Silicon.
    steam-asahi = {
      url = "github:sm-idk/steam-asahi/5e538015e267bfd57ccf49e5ed0660ac7fd9f8ea";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nur-unstable = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Keep llm-agents on its tested nixpkgs revision for binary-cache reuse.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Declarative user passwords are sops-encrypted (secrets/users.yaml); the
    # age private key lives outside the repo. nixpkgs follows our pin so the
    # lock gains exactly the sops-nix node and no kernel-relevant input moves.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Zed Preview tarball for aarch64 Linux, pinned to the immutable GitHub
    # release asset. zed.dev's `preview/latest` endpoint re-packs the tarball
    # on every release, so the locked narHash drifts out from under the lock
    # and every evaluation forcing the source dies on a hash mismatch.
    zed-preview-bin = {
      url = "https://github.com/zed-industries/zed/releases/download/v1.22.0-pre/zed-linux-aarch64.tar.gz";
      flake = false;
    };

    # Hyprland stays on the known-good package set for this Asahi system.
    hyprland-pinned-nixpkgs.url = "github:NixOS/nixpkgs/b12141ef619e0a9c1c84dc8c684040326f27cdcc";

    xontrib-jedi-src = {
      url = "github:xonsh/xontrib-jedi";
      flake = false;
    };
    xontrib-prompt-starship-src = {
      url = "github:anki-code/xontrib-prompt-starship";
      flake = false;
    };
    copier-templates-extensions-src = {
      url = "github:copier-org/copier-templates-extensions";
      flake = false;
    };
    mini-swe-agent-src = {
      url = "git+https://github.com/SWE-agent/mini-swe-agent.git?rev=a83fcae82d2a08f0ee0c688f9d137b3566c097f8";
      flake = false;
    };
  };

  outputs =
    inputs@{ nixverse, ... }:
    let
      # Nixverse requires `flakePath`, but a normal path retains source-copy
      # context and evaluates to an invalid deferred store path. Keep this
      # context-free string until Nixverse accepts a regular flake path.
      flakePath = builtins.unsafeDiscardStringContext (toString ./.);
    in
    nixverse.lib.load {
      inherit inputs flakePath;
      # Hosts are per-node (nodes/*/host.nix), so listing both systems only
      # fans the perSystem outputs out — the aarch64 host is never
      # instantiated on x86_64. Host-bound perSystem exports are guarded to
      # aarch64 in outputs/perSystem/*.
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
}
