# Repository overview

NixOS configuration for `nixos-btw`, an Apple Silicon (aarch64-linux) laptop, built on
the nixverse flake framework (github:hgl/nixverse, pinned) with Home Manager wired in as
a NixOS module. One host; per-system outputs for `aarch64-linux` and `x86_64-linux`.

## Flake layout

- `flake.nix` — inputs and `nixverse.lib.load`. The `flakePath`
  `unsafeDiscardStringContext` hack is required by nixverse (it concatenates the value
  into paths); do not "fix" it.
- `nodes/nixos-btw/` — the host: `host.nix` (system/channel),
  `configuration.nix` (Asahi hardware, firmware extraction, module imports),
  `hardware-configuration.nix` (filesystem UUIDs — never edited casually).
- `modules/nixos/system/` — system concerns with one owner each: `base.nix` (boot,
  swap tiering, network, users, nix settings), `desktop.nix` (GDM/Hyprland/Sway, fonts,
  session variables), `services.nix` (logind, PipeWire, bluetooth, autostarts),
  `packages.nix` (plain system package list), `gaming.nix` (steam-asahi stack).
- `modules/home/` — Home Manager: user packages, the opencode stack, and the
  Factory/Droid wiring (model routing, mutable-config merge, jev MCP).
- `overlays/` — package overlays (zed preview, codex, xontribs, hyprland pin, ...).
- `packages/` — standalone package definitions (extracted system scripts, mini-attune,
  and the portable Factory tooling: factory-config, factory-droid, jev-mcp).
- `outputs/perSystem/` — flake outputs split into a portable set (jev-mcp,
  factory-config, factory-droid; exposed on both systems) and a host-bound
  aarch64-only set (zed, steam-asahi, check wrappers, apps, devShell).
- `secrets/` + `.sops.yaml` — declarative credentials sops-encrypted in
  `secrets/users.yaml` (keys `becker_password`, `root_password`, stored as
  crypt hashes; login password unchanged). The age key lives outside the repo
  at `~/.config/sops/age/keys.txt` (never committed), with a local backup copy
  at `~/.config/sops/age/keys.txt.bak`; back it up off-machine — without it
  the secrets are undecryptable and a rebuild needing them fails. The sops
  wiring first activates at the next `nixos-rebuild switch`.
- `checks/` — the invariant check suite (below).
- `lib/default.nix` — overlay wiring.

## The frozen kernel boundary

`boot.kernelPackages` is never set in this repository. The kernel (linux-asahi), m1n1,
U-Boot, and the Asahi integration come from
`inputs.apple-silicon.modules.apple-silicon-support`, imported in
`nodes/nixos-btw/configuration.nix`. The nixpkgs and apple-silicon pins in `flake.lock`
are frozen; nothing here may build, activate, or switch a system closure.

## Validation philosophy

Evaluation-first: checks are assert chains that fire during evaluation, so
`nix flake show` — which forces every check's eval-assert layer — validates the whole
flake without realizing anything. Each check owns exactly one invariant family and is
classified by realization cost:

- **EVAL-ASSERT** — fires on evaluation: `system-invariants`, `asahi-gaming`,
  `factory-invariants`, `home-invariants`' table, `portable-packages-eval`.
- **LIGHT-BUILD** — realizes a small kernel-free derivation: `asahi-gaming`'s binary
  smoke test, `xonsh-config`, `desktop-osd-contract`, `alacritty-copybuffer`,
  `hyprland-gpu-preflight`, `opencode-context-stack-e2e`.
- **REBUILD-TIME** — interpolates `config.system.build.toplevel` by design:
  `gdm-greeter-preflight`, `switch-safety`, system-invariants' preflight script. These
  are the pre-switch safety net for real rebuilds; automation never builds them.

## Running checks safely

From the repo root:

    nix flake show       # evaluates all outputs; fires every eval-assert layer
    nix eval .#nixosConfigurations.nixos-btw.config.<path>   # any config value
    nix fmt -- --check   # format check

Never run: `nixos-rebuild` (any mode), `nix flake check` (it builds all checks,
including the REBUILD-TIME ones), `nix build` of `checks.*`, `nixosConfigurations.*`, or
the toplevel, and broad `nix flake update`. Targeted light builds of the portable
packages are safe:

    nix build .#packages.aarch64-linux.factory-config --no-link   # runs its unittests

Per-family details live in the check sources under `checks/`; the gaming stack is
described in `docs/asahi-gaming.md`.
