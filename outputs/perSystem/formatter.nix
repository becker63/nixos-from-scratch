# `nix fmt` entry point for the tree. nixfmt-classic is gone from the pinned
# nixpkgs (its alias now throws), so the RFC-style nixfmt owns the tree and
# the one-time whole-tree reformat landed in the commit that added this file.
# A thin wrapper is required because nix 2.34 forwards no file arguments (bare
# nixfmt would sit on stdin) while `nix fmt -- --check` forwards `--check`,
# which the treefmt-based nixfmt-tree wrapper rejects. Formatted from the
# plain perSystem pkgs (not the host's overlay pkgs) so the formatter stays
# portable across systems.
{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "formatter";

  runtimeInputs = [
    pkgs.git
    pkgs.nixfmt
  ];

  text = ''
    cd "''${PRJ_ROOT:-.}"

    # `nix fmt` forwards args verbatim: no args (format the tree) or `--check`
    # (verify the tree). Explicit file paths, if any, win over the tree walk.
    files=()
    check=false
    for arg in "$@"; do
      case "$arg" in
        --check) check=true ;;
        *) files+=("$arg") ;;
      esac
    done

    if [ "''${#files[@]}" -eq 0 ]; then
      # Tracked Nix files only — the formatter's jurisdiction ends at *.nix;
      # config/ (xonsh, hyprland, sway), JSON, python, rust, and docs have
      # their own owners.
      mapfile -t files < <(git ls-files '*.nix')
    fi

    [ "''${#files[@]}" -gt 0 ] || exit 0

    if [ "$check" = true ]; then
      exec nixfmt -c "''${files[@]}"
    else
      exec nixfmt "''${files[@]}"
    fi
  '';
}
