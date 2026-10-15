{ lib, pkgs, ... }:

{
  imports = [ ./desktop-common.nix ];
  programs.sway = {
    enable = true;
    package = pkgs.swayfx;
  };

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
  security.pam.services.gdm.enableGnomeKeyring = true;

  services.displayManager.gdm = {
    enable = true;
    # Debug logging stays on: greeter failures on this Asahi setup are
    # diagnosed from GDM's own logs, and checks/system-invariants.nix pins
    # this flag so a cleanup pass cannot silently drop it.
    debug = true;
  };

  # GDM's media-key daemon handles these keys before logind sees them.
  programs.dconf.profiles.gdm.databases = lib.mkBefore [
    (
      let
        emptyStringArray = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
      in
      {
        settings = {
          "org/gnome/settings-daemon/plugins/media-keys" = {
            suspend = emptyStringArray;
            suspend-static = emptyStringArray;
            hibernate = emptyStringArray;
            hibernate-static = emptyStringArray;
          };
          "org/gnome/settings-daemon/plugins/power" = {
            power-button-action = "nothing";
          };
        };
        lockAll = true;
      }
    )
  ];

  # GDM's greeter session file lives under share/gnome-session, and GNOME 50's
  # greeter handoff now actively searches the system profile for it.
  environment.pathsToLink = [ "/share/gnome-session" ];

}
