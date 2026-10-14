# AM4 / RTX 2080 Ti gaming box

Standalone x86_64 NixOS host and installer. Pinned Jovian provides the gaming
session, automatic login, and Switch to Desktop integration; Hyprland is the
desktop fallback. The Apple Silicon host and root flake pins are untouched.

## Status

The first ISO was built/flashed on 2026-10-14 with full USB readback verification
and a matching bundled nixpkgs NAR hash. Its custom Gamescope wrapper failed on the
actual gaming PC. The precise NVIDIA/Gamescope error still needs local diagnosis.

This branch switches to Jovian and includes the installation fixes: clearing old
ZFS signatures, explicit filesystem mounts, enabled Nix experimental features, and
a signature exception limited to copying the bundled source. Host and installer
evaluation passes. Jovian has not yet been built or activated on the gaming PC.
The original wrapper remains under `legacy/` for diagnosis.

## Experience

- SDDM autologin as `becker` into Jovian's `gamescope-wayland` session.
- Steam Switch to Desktop opens Hyprland; logging out returns to gaming.
- Alt+Shift+G and the Return to Gaming launcher log out of Hyprland.
- Your bindings, wallpaper, screenshots, launcher, terminal appearance, and volume
  overlay are exported in `desktop-config/`, independent of unrelated local edits.
- Ctrl+Alt+F2 gives an independent login TTY. Alt+Return or Alt+Shift+T opens a
  desktop terminal. The old custom repair menu is no longer used.
- NVIDIA modesetting/32-bit graphics, PipeWire, Bluetooth, GE-Proton, Protontricks,
  Heroic, Lutris, Wine, GameMode, and MangoHud are included.
- Steam Deck-specific hardware settings are disabled on this AM4 tower.
- Codex 0.162.0 installs through npm into `~/.npm-global` for becker only.

Steam still requires account login and downloads. Unsupported anti-cheat is not
made compatible by a session change. Switching sessions closes their applications.
There is no GNOME/KDE desktop session, though Jovian brings some desktop libraries
and tools. Bash is the repair shell; private dev tools, credentials, and custom
terminal patches are not exported.

## Pins and layout

`nixpkgs-pin.nix` snapshots the existing frozen source. `jovian-pin.nix` independently
pins Jovian's revision and NAR hash. `host.nix` is the target configuration;
`default.nix` exposes `host`, `installer`, `iso`, `offlineIso`, and `validation`.

## Repair and migrate the installed PC

Read this directory's `AGENTS.md`. The user authorized builds/switches on the
installed x86 gaming PC for this migration. Preserve disks, games, and home.
Do not rerun the disk installer. Keep raw diagnostic logs under ignored
`diagnostics/` and do not commit credentials.

Inspect `journalctl -b -u greetd`, `journalctl -b -k`, `nvidia-smi`,
`vulkaninfo --summary`, and the current `/etc/nixos` configuration. The old wrapper's
stdout may only have reached the console; reproduce on a spare TTY if needed.
Do not assume that installing Jovian resolves the underlying GPU error.

From the repository on the x86 gaming PC:

```sh
nix-instantiate --eval --strict --json gaming-installer -A validation
sudo nixos-rebuild build --file ./gaming-installer/default.nix --attr host
sudo nixos-rebuild switch --file ./gaming-installer/default.nix --attr host
```

Check filesystem labels and preserve machine-local overrides before switching.
Record hardware fixes declaratively here. Validate Steam, controllers, sound,
desktop switching, and TTY recovery on real hardware, then commit/push changes.
Future rebuilds must use this same expression; cloning the branch does not update
the old `/etc/nixos` configuration automatically.

## Codex from the TTY

As becker:

```sh
npm install -g --prefix "$HOME/.npm-global" @openai/codex@0.162.0
export PATH="$HOME/.npm-global/bin:$PATH"
codex login --device-auth
```

Use a browser on another device to finish login. If needed, `nix-shell -p nodejs git`
supplies missing Node/npm or Git. Codex and GitHub have separate authentication;
pushing contributions requires GitHub credentials on the PC.

## Checks and fresh installer

```sh
nix-instantiate --eval --strict --json gaming-installer -A validation
bash -n gaming-installer/install.sh gaming-installer/flash-pny.sh
python3 gaming-installer/test-filesystem-signatures.py
nixfmt --check gaming-installer/*.nix
```

The regression uses sparse temporary files, never physical disks: it reproduces
ext4 formatting leaving ZFS labels and verifies cleanup, filesystem types, and
labels. ShellCheck also validates the generated installer and helper scripts.

For a separately authorized fresh installer build:

```sh
nix-build gaming-installer -A iso -o result-gaming-iso --max-jobs 2 --cores 2
```

Image tools run natively and compression fails on read errors; the OS remains
x86_64. The default ISO downloads/builds the target on the AM4 PC.
`-A offlineIso` bundles the full target closure and needs substantially more storage.

`sudo bash gaming-installer/flash-pny.sh /absolute/path/to/image.iso` only targets
PNY serial AU3A092300000041, requires unmounted partitions, flushes cached blocks,
and compares every written byte. Boot in UEFI mode with Secure Boot disabled and
internet access. Confirm a disk and password; installation erases the whole disk:
GPT, 1 GiB FAT32 EFI, remaining space ext4, systemd-boot, and 25% zram. No Windows
preservation or dual boot. The original USB predates the fixes and Jovian migration.

## Local AI

Once gaming works, optionally set `services.ollama.enable = true;` and
`services.ollama.package = pkgs.ollama-cuda;` in host.nix and rebuild on the PC.
CUDA and model downloads are deferred from the installer.
