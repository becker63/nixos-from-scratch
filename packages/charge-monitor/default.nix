# charge-monitor: fullscreen terminal view of charge-status, refreshing on an
# interval. Depends on the charge-status package, which is not in nixpkgs, so
# the call site must pass it explicitly.
{
  writeShellScriptBin,
  charge-status,
}:
writeShellScriptBin "charge-monitor" ''
  #!/usr/bin/env bash
  set -euo pipefail

  interval="''${1:-2}"
  while true; do
    clear
    printf '\033[1;36mCharging monitor\033[0m  (refreshing every %ss; Ctrl-C to exit)\n\n' "$interval"
    ${charge-status}/bin/charge-status
    sleep "$interval"
  done
''
