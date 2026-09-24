# mini-attune: the configured mini-swe-agent launcher. This is the single
# shared definition — it was previously duplicated verbatim in
# modules/nixos/system/packages.nix and outputs/perSystem/packages.nix.
# It depends on the overlay packages mini-swe-agent and xonsh, so every
# call site must pass the host's overlay pkgs: the package is host-bound,
# not portable.
{
  writeText,
  writeShellApplication,
  mini-swe-agent,
  xonsh,
}:

let
  miniAttuneConfig = writeText "mini-attune.yaml" (
    builtins.readFile ../../config/minisweagent/attune.yaml
  );
in
writeShellApplication {
  name = "mini-attune";
  runtimeInputs = [
    mini-swe-agent
    xonsh
  ];
  text = ''
    # mini's setup wizard is global-state based, even with an explicit
    # config. This launcher is fully configured below, so bypass it.
    export MSWEA_CONFIGURED=true
    export MSWEA_SILENT_STARTUP=1
    export MSWEA_ATTUNE_CONVENTIONS=1

    if [ ! -f SPEC.md ]; then
      echo "mini-attune: SPEC.md is required at the project root" >&2
      exit 2
    fi

    if [ -f .env ]; then
      set -a
      # shellcheck source=/dev/null
      . ./.env
      set +a
    fi

    if [ -z "''${OPENROUTER_API_KEY:-}" ]; then
      echo "mini-attune: add OPENROUTER_API_KEY=... to this project's .env" >&2
      exit 2
    fi

    exec mini --yolo --exit-immediately --config '${miniAttuneConfig}' "$@"
  '';
}
