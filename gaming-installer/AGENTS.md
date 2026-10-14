# Gaming-box scope

This directory is the standalone x86_64 AM4 / RTX 2080 Ti gaming configuration.
The user explicitly authorized repairing the installed gaming PC, migrating it to
Jovian, and committing/pushing the reproducible fixes to the gaming-jovian branch.

- On the x86_64 gaming-box PC, builds and system switches for this directory are
  authorized. Inspect the current configuration and logs before activating changes.
- Do not rerun install.sh, repartition, format, or erase disks to repair an already
  installed machine. Preserve /home, games, credentials, and the current disk layout.
- On the Apple Silicon laptop, evaluate this configuration only; never switch the
  laptop or build its host closure. The original installer build exception does not
  authorize rebuilding the Apple Silicon host.
- Keep the root flake.nix/flake.lock, nixpkgs/Apple Silicon/steam-asahi pins, and
  Factory mission processes unchanged. Jovian has its own pin in this directory.
- Keep Codex managed by npm in ~/.npm-global. Do not commit auth caches, passwords,
  Steam account data, journal dumps containing secrets, or machine-private files.
- Capture required NVIDIA/Gamescope fixes declaratively here; avoid undocumented
  one-off edits to /etc. Evaluate before switching, then validate on real hardware.
- Use the standalone host output, not the nixos-btw host or root deployment apps.
