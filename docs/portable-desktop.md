# Shared desktop module

Consumers pin this repository's commit as a flake input and import
`inputs.laptop.nixosModules.desktop`. The module exports Home Manager integration,
the laptop's pinned Hyprland packages, patched Alacritty, fonts, portals and Wayland
environment. It imports neither Asahi hardware nor the laptop's account secrets,
GDM, kernel, storage, networking or unrelated research tools.

Declare the normal `becker` account in the consumer, then set:

```nix
home-manager.users.becker.becker.desktop.portable = true;
```

This uses the actual `config/` dotfiles from the pinned input in the Nix store.
Hyprland's existing appearance, keybindings and wallpaper are retained. A small
transformation removes Apple lid/keyboard/display overrides and selects automatic
monitor detection at scale 1. Consumers may append session rules using
`home-manager.users.becker.becker.desktop.extraHyprlandConfig`.

The laptop imports the same Home Manager profile with `portable = false` by default:
its existing live checkout links and hardware-specific configuration stay in use.
The Home Manager profile is also exported as `homeManagerModules.desktop` for
consumers that already manage their system integration themselves.

The consuming system owns login policy, UWSM, account UID/groups, credentials,
sudo and graphical startup. No password or password hash is exported. Zed uses the
consumer's pinned `zed-editor` package; the laptop's ARM-only preview package is
not imposed on x86 machines. Its existing Zed settings are shared.

`checks.{aarch64-linux,x86_64-linux}.portable-desktop` evaluates the module in a
hardware-neutral NixOS configuration. For example:

```sh
nix eval .#checks.x86_64-linux.portable-desktop.drvPath --raw
nix eval .#checks.aarch64-linux.portable-desktop.drvPath --raw
```

These contracts check package/configuration composition, store-backed dotfiles,
and separation from hardware, login manager and passwords. They do not prove
graphical startup or GPU compatibility. The appliance must test those separately.
No laptop system closure needs to be built or activated for this export.
