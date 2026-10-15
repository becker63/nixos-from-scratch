# Cheap cross-architecture reproducibility (no kernel build)

The repository's real laptop target is `nixos-btw` (`aarch64-linux`, Asahi/Apple Silicon). The `x86_64-linux` flake outputs are **portable tool packages**, not an x86 replacement for that Apple-specific kernel, firmware, boot chain, or physical machine. A full NixOS derivation can be *evaluated* on a different CPU without executing target instructions; that does **not** establish runtime correctness or successful builds.

## First pass: no emulation, no build

From a clean checkout on either ARM64 or x86_64 Linux:

```sh
bash scripts/repro-eval.sh all
```

`portable` only evaluates **every** `packages.x86_64-linux.*.drvPath` and the `portable-packages-eval` assertion. `host` only evaluates the laptop's ARM64 system derivation and confirms its target architecture. `all` does both. Each mode uses `--no-write-lock-file` and explicitly disables import-from-derivation (which otherwise can trigger a build *during evaluation*). The script executes no Nix build, kernel build, system activation, emulator, test runner, or disk operation. Network input downloads may still happen on a cold store.

A native GitHub Actions x86_64 runner executes the same evaluation-only script for relevant pull requests and manual dispatch; it installs Nix but does not build any derivations. This is a clean-checkout evaluation test, **not** an x86 boot or binary execution test.

## Escalation, only after evaluation works

1. For each portable package that matters, check whether its target outputs are already present in a trusted binary cache. A successful evaluation alone says nothing about substitutability. Do not confuse `nix build --dry-run` with execution of a test.
2. If execution is required, test one small portable package on a native x86_64 builder (e.g. the separate gaming PC) rather than starting with a full closure. Keep test output and a manifest of system, flake revision, cache hits/misses, and derivation path.
3. Only as a fallback investigate x86 translation. The current bare-metal Asahi install cannot use Apple's macOS Virtualization.framework Rosetta service. `cpick/nix-rosetta-builder` is a **macOS**-hosted solution using an ARM Linux guest. Asahi's 16 KiB host-page complications, QEMU/V8 failures, and FEX/esbuild failures are separately documented in `docs/jev-swe-mini.md` and `docs/jev-swe-max.md`.

Avoid using `nix flake check` or `nixos-rebuild` as a cheap preflight: the former includes rebuild-time checks that refer to the full host closure, and the latter constructs/activates a system. Never update `flake.lock`, the Apple-Silicon/Asahi pin, or passwords just to make this test pass. The sops age private key is intentionally **not** stored in Git; an evaluation pass does not prove a fresh machine can decrypt secrets or boot.

## Publication boundary

This is safe to commit alongside other text-only tooling. Before committing any local work, run `git status --short`, inspect the staged diff and ignored/untracked paths, and check that no plaintext credentials, tokens, private keys, host journals, or personal runtime state are included. A Repomix snapshot is not a substitute for the actual local Git index; it cannot prove uncommitted files were pushed.
