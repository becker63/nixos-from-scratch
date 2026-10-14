{
  nixpkgsSource ? (import ./nixpkgs-pin.nix).outPath,
  desktopSource ? ./desktop-config,
  wallpaper ? ../walls/arnold-bocklin-isle-of-the-dead.jpg,
  offline ? false,
  assemblySystem ? builtins.currentSystem,
  jovianSource ? (import ./jovian-pin.nix).outPath,
}:
let
  system = "x86_64-linux";
  pkgs = import nixpkgsSource {
    inherit system;
    config.allowUnfree = true;
  };
  lib = pkgs.lib;
  # Image compression and ISO assembly run on the builder's actual CPU.
  # qemu-user on this 16 KiB-page ARM host can silently lose file contents in
  # an emulated mksquashfs. Only the image tools are native; its OS is x86_64.
  imagePkgs = import nixpkgsSource { system = assemblySystem; };
  hostModule = import ./host.nix;
  specialArgs = {
    inherit
      desktopSource
      wallpaper
      nixpkgsSource
      jovianSource
      ;
  };
  host = import (nixpkgsSource + "/nixos/lib/eval-config.nix") {
    inherit system specialArgs;
    modules = [ hostModule ];
  };
  installer = import (nixpkgsSource + "/nixos/lib/eval-config.nix") {
    inherit system;
    modules = [
      (nixpkgsSource + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
      (
        { config, ... }:
        let
          install = pkgs.writeShellApplication {
            name = "install-gaming-box";
            runtimeInputs = with pkgs; [
              coreutils
              util-linux
              parted
              dosfstools
              e2fsprogs
              openssl
              gnugrep
              gawk
              systemd
              gnused
              curl
            ];
            text =
              lib.replaceStrings
                [ "@INSTALL@" "@NETWORKCHECK@" "@SOURCE@" "@DESKTOP@" "@WALLPAPER@" "@NIXPKGS@" ]
                [
                  (
                    if offline then
                      "nixos-install --root /mnt --system ${host.config.system.build.toplevel} --no-root-passwd --no-channel-copy"
                    else
                      "nixos-install --root /mnt --file /mnt/etc/nixos/system.nix --no-root-passwd --no-channel-copy"
                  )
                  (
                    if offline then
                      ":"
                    else
                      ''
                        curl --fail --silent --show-error --head --max-time 15 https://cache.nixos.org/nix-cache-info >/dev/null || {
                          echo 'Internet is required. Connect Ethernet or use nmtui, then run install-gaming-box again.' >&2
                          exit 1
                        }
                      ''
                  )
                  "${./.}"
                  "${desktopSource}"
                  "${wallpaper}"
                  "${nixpkgsSource}"
                ]
                (builtins.readFile ./install.sh);
          };
        in
        {
          networking.hostName = "gaming-installer";
          nix.settings.experimental-features = [
            "nix-command"
            "flakes"
          ];
          boot.zfs.forceImportRoot = false;
          image.baseName = lib.mkForce "nixos-am4-gaming${lib.optionalString offline "-offline"}-x86_64";
          isoImage.volumeID = "NIXOS_GAMING_INSTALL";
          isoImage.makeEfiBootable = true;
          isoImage.makeUsbBootable = true;
          isoImage.squashfsCompression = "zstd -Xcompression-level 6 -exit-on-error";
          isoImage.storeContents = [
            nixpkgsSource
          ]
          ++ lib.optional offline host.config.system.build.toplevel;
          environment.systemPackages = [ install ];
          systemd.services."getty@tty1".enable = false;
          systemd.services."autovt@tty1".enable = false;
          systemd.services.gaming-install = {
            description = "Interactive disk selection followed by gaming-box installation";
            wantedBy = [ "multi-user.target" ];
            after = [ "systemd-user-sessions.service" ];
            serviceConfig = {
              Type = "idle";
              StandardInput = "tty";
              StandardOutput = "tty";
              StandardError = "tty";
              TTYPath = "/dev/tty1";
              TTYReset = true;
              TTYVHangup = true;
            };
            script = ''
              ${lib.getExe install} || true
              exec ${pkgs.bashInteractive}/bin/bash -il
            '';
          };
          services.getty.helpLine = lib.mkForce ''
            AM4 / RTX 2080 Ti gaming installer
            Run: sudo install-gaming-box
            It asks for a target disk and password, then installs the gaming system.
            Network setup if needed: nmtui
          '';
          networking.networkmanager.enable = true;
          networking.wireless.enable = lib.mkForce false;
          services.openssh.enable = lib.mkForce false;
          system.stateVersion = "26.05";
        }
      )
    ];
  };
in
rec {
  inherit host installer hostModule;
  iso = imagePkgs.callPackage (nixpkgsSource + "/nixos/lib/make-iso9660-image.nix") {
    isoName = "${installer.config.image.baseName}.iso";
    inherit (installer.config.isoImage) contents volumeID;
    squashfsContents = installer.config.isoImage.storeContents;
    squashfsCompression = installer.config.isoImage.squashfsCompression;
    bootable = true;
    bootImage = "/isolinux/isolinux.bin";
    # syslinux is x86 boot data, not an executable image-assembly tool.
    syslinux = pkgs.syslinux;
    usbBootable = true;
    isohybridMbrImage = "${pkgs.syslinux}/share/syslinux/isohdpfx.bin";
    efiBootable = true;
    efiBootImage = "boot/efi.img";
  };
  offlineIso =
    (import ./. {
      inherit
        nixpkgsSource
        desktopSource
        wallpaper
        assemblySystem
        jovianSource
        ;
      offline = true;
    }).iso;
  validation = {
    system = host.pkgs.stdenv.hostPlatform.system;
    failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) host.config.assertions);
    installerFailedAssertions = map (a: a.message) (
      builtins.filter (a: !a.assertion) installer.config.assertions
    );
    inherit (host.config.hardware.nvidia) open modesetting;
    driver = host.config.hardware.nvidia.package.version;
    steam = host.config.programs.steam.enable;
    graphics32Bit = host.config.hardware.graphics.enable32Bit;
    defaultSession = host.config.services.displayManager.defaultSession;
    jovian = host.config.jovian.steam.enable;
    desktopSession = host.config.jovian.steam.desktopSession;
    isoName = installer.config.image.baseName;
    hostDerivation = host.config.system.build.toplevel.drvPath;
    isoDerivation = iso.drvPath;
    imageAssemblySystem = assemblySystem;
  };
}
