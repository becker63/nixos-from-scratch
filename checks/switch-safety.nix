{ checks, pkgs }:

let
  lib = pkgs.lib;

  verificationScript = lib.concatMapStringsSep "\n" (
    name:
    let
      result = checks.${name};
    in
    ''
      if [ ! -f '${result}/result' ]; then
        echo 'FAIL: ${name} did not produce its result marker' >&2
        exit 1
      fi
      printf 'PASS: %s\n' '${name}'
    ''
  ) (lib.attrNames checks);

  package = pkgs.writeShellApplication {
    name = "switch-safety";
    text = ''
      set -euo pipefail

      ${verificationScript}
      printf 'PASS: the candidate generation satisfies every switch-safety contract\n'
    '';
  };

  check = pkgs.runCommand "switch-safety-check" { } ''
    set -euo pipefail
    ${package}/bin/switch-safety
    mkdir -p "$out"
    echo ok > "$out/result"
  '';
in
{
  inherit package check;
}
