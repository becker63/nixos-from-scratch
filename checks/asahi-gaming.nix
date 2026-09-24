{ config, pkgs }:

let
  lib = pkgs.lib;
  cfg = config.programs.steam-asahi;
  packageName = package: package.pname or (lib.getName package);
  doctor = lib.findFirst (
    package: packageName package == "asahi-gaming-doctor"
  ) null config.environment.systemPackages;

  expect =
    condition: message:
    assert lib.assertMsg condition message;
    true;
in
assert expect cfg.enable "steam-asahi must be enabled";
assert expect (cfg.memoryMiB == 5 * 1024) "steam-asahi must leave host/compositor memory headroom";
assert expect (
  !config.programs.steam.enable
) "native programs.steam must remain disabled on aarch64";
assert expect (
  !config.hardware.graphics.enable32Bit
) "host 32-bit graphics must remain disabled; FEX supplies the x86 userspace";
assert expect (builtins.elem "kvm" config.users.users.becker.extraGroups)
  "becker must have KVM access";
assert expect config.hardware.asahi.enable "Asahi hardware support must remain enabled";
assert expect config.hardware.graphics.enable "host graphics acceleration must remain enabled";
# Kernel-pname defense-in-depth: checks/system-invariants.nix owns the
# kernel-pname assert for the whole system; this duplicate guards it
# specifically against replacement by the gaming stack. Keep both in sync.
assert expect (
  config.boot.kernelPackages.kernel.pname == "linux-asahi"
) "the gaming stack must not replace linux-asahi";
# Swap/zram invariants (enable, algorithm, size, priority tiering) are owned
# by checks/system-invariants.nix — do not duplicate them here.
assert expect (
  config.boot.kernel.sysctl."vm.max_map_count" == 1048576
) "the Proton map-count limit must be configured";
assert expect (
  config.boot.kernel.sysctl."vm.watermark_scale_factor" == 125
) "the gaming memory watermark must be configured";
assert expect (doctor != null) "asahi-gaming-doctor must be installed";
pkgs.runCommand "asahi-gaming-stack-check" { } ''
  set -euo pipefail

  test -x ${cfg.package}/bin/steam-asahi
  test -x ${pkgs.muvm}/bin/muvm
  test -x ${pkgs.fex}/bin/FEXBash
  test -x ${doctor}/bin/asahi-gaming-doctor

  ${doctor}/bin/asahi-gaming-doctor --help \
    | grep -F 'host|guest|fex|network|gpu|all' >/dev/null

  mkdir -p "$out"
  printf 'ok\n' > "$out/result"
''
