{
  inputs',
  modules',
  pkgs,
  ...
}:

let
  inputs = inputs';
  peripheralFirmwareSource = ../../firmware;
  peripheralFirmware =
    pkgs.runCommand "asahi-peripheral-firmware-source"
      {
        nativeBuildInputs = [ pkgs.asahi-fwextract ];
      }
      ''
        mkdir -p "$out"
        cp ${peripheralFirmwareSource}/all_firmware.tar.gz \
          ${peripheralFirmwareSource}/kernelcache.release.mac14g "$out/"
        asahi-fwextract ${peripheralFirmwareSource} "$out"
      '';
in
{
  imports = [
    modules'.overlays
    modules'.system
    inputs.apple-silicon.modules.apple-silicon-support
    inputs.steam-asahi.modules.default
    # Decrypts secrets/users.yaml for the declarative user passwords in
    # modules/nixos/system/base.nix. nixverse re-exposes each input's
    # nixosModules as `modules`, so this is inputs.sops-nix.modules.sops.
    inputs.sops-nix.modules.sops
  ];

  _module.args.nixosBtwFlakeBuild = true;

  hardware.asahi = {
    enable = true;
    # asahi-fwextract 0.8 expects a pre-extracted firmware.cpio. Generate it
    # reproducibly from the tracked installer artifacts before the module's
    # firmware derivation consumes the directory.
    peripheralFirmwareDirectory = peripheralFirmware;
    setupAsahiSound = true;
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      mesa
      libva
      libva-utils
    ];
  };

  # PipeWire is owned by modules/nixos/system/services.nix (which carries the
  # superset: 32-bit ALSA support, JACK off); QT_QPA_PLATFORM is owned by
  # modules/nixos/system/desktop.nix, where qt is configured.
  environment.sessionVariables = {
    LV2_PATH = "${pkgs.asahi-audio}/lib/lv2";
    LIBVA_DRIVER_NAME = "asahi";
    MESA_LOADER_DRIVER_OVERRIDE = "asahi";
    VDPAU_DRIVER = "va_gl";
  };

  home-manager.backupFileExtension = "backup";
}
