final: prev:
let
  # GNOME 50's greeter session starts `gnome-session` by name. On NixOS the
  # compiled GDM fallback PATH currently misses the standard NixOS runtime
  # profile directories, which leaves us with a blank cursor and no login
  # prompt once the greeter tries to exec `gnome-session`.
  gdmFallbackPath = "/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin";
in
{
  gdm = prev.gdm.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or [ ]) ++ [
      "-Ddefault-path=${gdmFallbackPath}"
    ];
    patches = (old.patches or [ ]) ++ [
      ./gdm-forward-xdg-data-dirs.patch
    ];
  });
}
