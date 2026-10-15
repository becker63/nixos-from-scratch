{
  lib,
  python3Packages,
  pkgs,
  makeWrapper,
}:
let
  history = python3Packages.buildPythonApplication {
    pname = "buildbuddy-history";
    version = "0.1.0";
    pyproject = true;
    src = ./.;
    build-system = [ python3Packages.setuptools ];
    dependencies = with python3Packages; [
      httpx
      mcp
      pandas
      pyarrow
      numpy
      scipy
      matplotlib
    ];
    nativeBuildInputs = [ makeWrapper ];
    nativeCheckInputs = with python3Packages; [
      pytestCheckHook
      pytest-asyncio
    ];
    pythonImportsCheck = [ "buildbuddy_history.server" ];
    postFixup = ''
      wrapProgram "$out/bin/buildbuddy-history-tunnel" \
        --set HISTORY_TUNNEL_CLIENT ${pkgs.callPackage ../tunnel-client { }}/bin/tunnel-client \
        --set HISTORY_MCP_COMMAND "$out/bin/buildbuddy-history" \
        --set HISTORY_SYSTEMCTL ${pkgs.systemd}/bin/systemctl
    '';
    meta = {
      description = "Read-only native BuildBuddy invocation history MCP and chronological analysis";
      license = lib.licenses.mit;
      mainProgram = "buildbuddy-history";
      platforms = [
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
  };
  services = import ./services.nix { package = history; };
  timer = {
    Unit = {
      Description = "Check independent history tunnel readiness";
      ConditionPathExists = "%h/.config/tunnel-client/buildbuddy-history.json";
    };
    Timer = {
      OnStartupSec = 60;
      OnUnitActiveSec = 60;
      Unit = "buildbuddy-history-health.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
  ini = pkgs.formats.ini { };
  normalize = lib.mapAttrs (
    _: lib.mapAttrs (_: value: if builtins.isList value then lib.concatStringsSep " " value else value)
  );
  unitFiles = (
    lib.mapAttrsToList (name: value: {
      name = "${name}.service";
      path = ini.generate "${name}.service" (normalize value);
    }) services
    ++ [
      {
        name = "buildbuddy-history-health.timer";
        path = ini.generate "buildbuddy-history-health.timer" (normalize timer);
      }
    ]
  );
  serviceUnits = pkgs.runCommand "buildbuddy-history-service-units" { } ''
    mkdir -p "$out"
    ${lib.concatStringsSep "\n" (map (unit: ''cp ${unit.path} "$out/${unit.name}"'') unitFiles)}
  '';
in
history.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit serviceUnits timer;
  };
})
