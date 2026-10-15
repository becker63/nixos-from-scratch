{
  lib,
  nodes,
  outputs',
  system,
  ...
}:

# The dev shell uses the aarch64 host's overlay pkgs (python-env is an
# overlay package), so it is host-bound; x86_64 exposes no dev shell.
let
  researchPython = nodes.nixos-btw.pkgs.python313.withPackages (ps: [
    ps.textual
    ps.textual-plotext
  ]);
in
lib.optionalAttrs (system == "aarch64-linux") {
  default = nodes.nixos-btw.pkgs.mkShell {
    packages = with nodes.nixos-btw.pkgs; [
      researchPython
      python-env
      rustc
      cargo
      rustfmt
      clippy
      outputs'.packages.research-textual
      outputs'.packages.research-ratatui
    ];
  };
}
