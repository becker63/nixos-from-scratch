# Repository safeguards

- Never change the pinned kernel or its input pins. Keep `flake.lock`, the nixpkgs and apple-silicon pins, and the steam-asahi pin unchanged. Do not build or switch a system closure; see `docs/repository.md`.
- Preserve existing Factory mission processes. Do not kill, restart, or interrupt them during CLI maintenance.
- Codex CLI is managed by npm under `~/.npm-global`; Droid stays managed by Nix. Preserve the Factory Jev credential launcher.
