{
  lib,
  pkgs,
  stdenvNoCC,
  python3,
  makeWrapper,
  systemd,
}:
let
  tunnelClient = pkgs.callPackage ../tunnel-client { };
  nativeMcp = pkgs.callPackage ./native.nix { };
  units = import ./services.nix { helper = "@helper@"; };
  timer = {
    Unit = {
      Description = "Check Jev tunnel every minute";
      ConditionPathExists = "%h/.config/tunnel-client/jev.json";
    };
    Timer = {
      OnStartupSec = 60;
      OnUnitActiveSec = 60;
      Unit = "jev-tunnel-health.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
  ini = pkgs.formats.ini { };
  normalize = lib.mapAttrs (
    _: lib.mapAttrs (_: value: if builtins.isList value then lib.concatStringsSep " " value else value)
  );
  files =
    lib.mapAttrs' (
      name: value: lib.nameValuePair "${name}.service" (ini.generate "${name}.service" (normalize value))
    ) units
    // {
      "jev-tunnel-health.timer" = ini.generate "jev-tunnel-health.timer" (normalize timer);
    };
in
stdenvNoCC.mkDerivation {
  pname = "jev-tunnel";
  version = "0.1.0";
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    mkdir -p "$out/libexec" "$out/share/systemd/user"
    cp ${./tunnel.py} "$out/libexec/jev-tunnel.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/jev-tunnel" \
      --add-flags "$out/libexec/jev-tunnel.py" \
      --add-flags "--tunnel-client ${tunnelClient}/bin/tunnel-client" \
      --add-flags "--mcp-command ${nativeMcp}/bin/jev-native-mcp" \
      --add-flags "--systemctl ${systemd}/bin/systemctl" \
      --add-flags "--unit-dir $out/share/systemd/user"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: file: ''
        if [ "${name}" = jev-tunnel-health.timer ]; then
          cp ${file} "$out/share/systemd/user/${name}"
        else
          substitute ${file} "$out/share/systemd/user/${name}" --replace-fail @helper@ "$out/bin/jev-tunnel"
        fi
      '') files
    )}
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    ${python3}/bin/python3 ${./tests/profile_client_check.py} "$out/bin/jev-tunnel" ${tunnelClient}/bin/tunnel-client
  '';
  passthru = { inherit nativeMcp tunnelClient timer; };
  meta = {
    description = "Nix-managed native Jev Secure MCP Tunnel service and setup";
    mainProgram = "jev-tunnel";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    license = lib.licenses.mit;
  };
}
