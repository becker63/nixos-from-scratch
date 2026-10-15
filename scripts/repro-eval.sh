#!/usr/bin/env bash
# Evaluate repository reproducibility without realizing a Nix derivation.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mode="${1:-all}"
case "$mode" in
  all|portable|host) ;;
  *) echo 'usage: scripts/repro-eval.sh [all|portable|host]' >&2; exit 2 ;;
esac

# IFD can execute builders *during* evaluation. Disable it explicitly.
# No nix build, flake check, nixos-rebuild, or activation command belongs here.
nix_eval() {
  command nix --extra-experimental-features 'nix-command flakes' \
    --option allow-import-from-derivation false \
    eval --no-write-lock-file "$@"
}

if [[ "$mode" == all || "$mode" == portable ]]; then
  echo 'Evaluating every x86_64-linux portable package derivation (no build)...'
  # mapAttrs forces all .drvPath values, unlike a superficial attr-name check.
  nix_eval --json \
    --apply 'packages: builtins.mapAttrs (_: package: package.drvPath) packages' \
    '.#packages.x86_64-linux' >/dev/null
  # Also forces assertions in the existing cross-architecture package contract.
  nix_eval --raw '.#checks.x86_64-linux.portable-packages-eval.drvPath' >/dev/null
  echo 'PASS: all portable x86_64 package derivations and invariant assertions evaluated.'
fi

if [[ "$mode" == all || "$mode" == host ]]; then
  echo 'Evaluating ARM64 NixOS host derivation from this checkout (no build)...'
  host_arch="$(nix_eval --raw '.#nixosConfigurations.nixos-btw.config.nixpkgs.hostPlatform.system')"
  if [[ "$host_arch" != aarch64-linux ]]; then
    echo "FAIL: expected aarch64-linux laptop; evaluated $host_arch" >&2
    exit 1
  fi
  nix_eval --raw '.#nixosConfigurations.nixos-btw.config.system.build.toplevel.drvPath' >/dev/null
  echo 'PASS: pinned Asahi host evaluates; its kernel and system closure were NOT built.'
fi

# Evaluating a flake may fetch inputs. The lockfile must not be rewritten.
if [[ -n "$(git status --porcelain -- flake.lock)" ]]; then
  echo 'FAIL: flake.lock changed during evaluation; restore and review separately.' >&2
  exit 1
fi
