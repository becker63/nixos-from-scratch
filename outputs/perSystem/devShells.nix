{
  lib,
  nodes,
  system,
  ...
}:

# The dev shell uses the aarch64 host's overlay pkgs (python-env is an
# overlay package), so it is host-bound; x86_64 exposes no dev shell.
lib.optionalAttrs (system == "aarch64-linux") {
  default = nodes.nixos-btw.pkgs.mkShell {
    packages = [ nodes.nixos-btw.pkgs.python-env ];
  };
}
