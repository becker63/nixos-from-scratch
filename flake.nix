{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Upstream Zed Preview tarball (aarch64 Linux). The `latest` URL is a
    # redirect to the current preview build; running
    #   nix flake update zed-preview-bin
    # refetches it and updates the locked narHash. If `latest` ever stops
    # resolving cleanly, swap in an explicit version, e.g.
    #   url = "https://zed.dev/api/releases/preview/0.221.5/zed-linux-aarch64.tar.gz";
    zed-preview-bin = {
      url = "https://zed.dev/api/releases/preview/latest/zed-linux-aarch64.tar.gz";
      flake = false;
    };

    apple-silicon = {
      url = "github:tpwrules/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    paseo = {
      url = "github:getpaseo/paseo?ref=v0.1.59";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 👇 pinned nixpkgs at Mesa 25.1.9
    mesa-pinned.url = "github:NixOS/nixpkgs/0170f90d6c3e56b98289f8956d1add375fcfb423";

    xontrib-jedi-src = {
      url = "github:xonsh/xontrib-jedi";
      flake = false;
    };

    xontrib-prompt-starship-src = {
      url = "github:anki-code/xontrib-prompt-starship";
      flake = false;
    };

    xontrib-output-search-src = {
      url = "github:anki-code/xontrib-output-search";
      flake = false;
    };

    # xontrib-output-search-src dep
    tokenize-output-src = {
      url = "github:anki-code/tokenize-output";
      flake = false;
    };

    arttime-src = {
      url = "github:poetaman/arttime";
      flake = false;
    };

    copier-templates-extensions-src = {
      url = "github:copier-org/copier-templates-extensions";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "aarch64-linux";

      overlays = [
        inputs.nur.overlays.default

        (final: prev: {
          paseo = (prev.callPackage "${inputs.paseo}/nix/package.nix" { }).overrideAttrs (old: rec {
            npmDepsHash = "sha256-kw9Lefo644oeeTJCvdFdeW4tbwVMQWqkIVaNonhqbNs=";
            npmDeps = prev.fetchNpmDeps {
              src = old.src;
              name = "paseo-0.1.59-npm-deps";
              hash = npmDepsHash;
              fetcherVersion = 1;
            };
          });
        })

        (import ./overlays/paseo-desktop.nix {
          paseo-src = inputs.paseo;
          version = "0.1.59";
        })

        (import ./overlays/xontribs-and-pkgs.nix {
          inherit (inputs)
            xontrib-jedi-src
            xontrib-prompt-starship-src
            xontrib-output-search-src
            tokenize-output-src
            copier-templates-extensions-src
            ;
        })
        (import ./overlays/my-xonsh.nix)
        (import ./overlays/arttime.nix { inherit (inputs) arttime-src; })
        (import ./overlays/scripts.nix)
        (import ./overlays/hascard.nix)
        (import ./overlays/zed-dual.nix {
          inherit (inputs) zed-preview-bin;
        })

        #(import ./overlays/mesa.nix { inherit (inputs) mesa-pinned; })
      ];

      pkgs = import nixpkgs { inherit system overlays; };
    in
    {
      packages.${system} = {
        inherit (pkgs) zed zed_raw zed-deps-report;
      };

      apps.${system}.zed-deps-report = {
        type = "app";
        program = "${pkgs.zed-deps-report}/bin/zed-deps-report";
      };

      nixosConfigurations.nixos-btw = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit (inputs) xontrib-jedi-src arttime-src;
          xontrib-fish-completer-src = inputs.xontrib-fish-completer-src;
        };
        modules = [
          inputs.apple-silicon.nixosModules.apple-silicon-support
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            hardware.asahi = {
              peripheralFirmwareDirectory = ./firmware;
              setupAsahiSound = true;
            };

            services.pipewire = {
              enable = true;
              alsa.enable = true;
              pulse.enable = true;
              wireplumber.enable = true;
            };

            environment.sessionVariables = {
              LV2_PATH = "${pkgs.asahi-audio}/lib/lv2";
            };

            hardware.graphics = {
              enable = true;
              extraPackages = with pkgs; [
                mesa
                libva
                libva-utils
              ];
            };

            environment.sessionVariables = {
              LIBVA_DRIVER_NAME = "asahi";
              MESA_LOADER_DRIVER_OVERRIDE = "asahi";
              VDPAU_DRIVER = "va_gl";
              QT_QPA_PLATFORM = "wayland";
            };

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.becker = import ./home.nix;
            home-manager.backupFileExtension = "backup";

            # 👇 add overlays to nixosSystem too
            nixpkgs.overlays = overlays;
          }
        ];
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ pkgs.python-env ];
      };
    };
}
