{
  inputs',
  modules',
  pkgs,
  ...
}:

let
  inputs = inputs';
in
{
  imports = [
    modules'.overlays
    modules'.system
    inputs.apple-silicon.modules.apple-silicon-support
  ];

  _module.args.nixosBtwFlakeBuild = true;

  hardware.asahi = {
    peripheralFirmwareDirectory = ../../firmware;
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

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  environment.sessionVariables = {
    LV2_PATH = "${pkgs.asahi-audio}/lib/lv2";
    LIBVA_DRIVER_NAME = "asahi";
    MESA_LOADER_DRIVER_OVERRIDE = "asahi";
    VDPAU_DRIVER = "va_gl";
    QT_QPA_PLATFORM = "wayland";
  };

  home-manager.backupFileExtension = "backup";
}
