{
  pkgs,
  lib,
  hyprlandPackage,
  hyprConfigFile,
  sessionVariables,
  validatedHyprlandVersions ? [ "0.54.3" ],
}:
let
  hyprlandVersion =
    if hyprlandPackage ? version then hyprlandPackage.version else lib.getVersion hyprlandPackage;

  renderedSessionVariables = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "${name}=${toString value}") sessionVariables
  );

  sessionVariablesFile = pkgs.writeText "hyprland-gpu-preflight-session-vars" renderedSessionVariables;

  validatedVersionsText = lib.concatStringsSep " " validatedHyprlandVersions;

  preflight = pkgs.writeShellApplication {
    name = "hyprland-gpu-preflight";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      gnused
    ];
    text = ''
      set -euo pipefail

      fail() {
        echo "FAIL: $*" >&2
        exit 1
      }

      note() {
        echo "INFO: $*"
      }

      hyprland_version='${hyprlandVersion}'
      hyprland_path='${hyprlandPackage}'
      hypr_config='${hyprConfigFile}'
      validated_versions='${validatedVersionsText}'

      has_split_gpu_topology=0
      if [ -e /sys/devices/platform/soc/206400000.gpu/drm/card1 ] && [ -e /sys/devices/platform/soc/soc:display-subsystem/drm/card2 ]; then
        has_split_gpu_topology=1
      fi

      has_drm_override=0
      if grep -Eq '^[[:space:]]*env[[:space:]]*=[[:space:]]*AQ_DRM_DEVICES,' "$hypr_config"; then
        has_drm_override=1
      fi

      if grep -Eq '^AQ_DRM_DEVICES=' '${sessionVariablesFile}'; then
        has_drm_override=1
      fi

      is_validated_version=0
      for candidate in $validated_versions; do
        if [ "$hyprland_version" = "$candidate" ]; then
          is_validated_version=1
          break
        fi
      done

      note "target Hyprland package: $hyprland_path"
      note "target Hyprland version: $hyprland_version"
      note "validated Hyprland versions for split Apple GPU topologies: $validated_versions"

      if [ "$has_split_gpu_topology" -eq 1 ]; then
        note "detected split Apple GPU topology: /dev/dri/card2 scanout + /dev/dri/card1 render"
      else
        note "split Apple GPU topology not detected on the currently running host"
      fi

      if [ "$has_drm_override" -eq 1 ]; then
        note "AQ_DRM_DEVICES is declared in the target generation"
      else
        note "AQ_DRM_DEVICES is not declared in the target generation"
      fi

      if [ "$is_validated_version" -eq 1 ]; then
        note "target Hyprland version is in the validated set"
        exit 0
      fi

      if [ "$has_drm_override" -eq 1 ]; then
        note "allowing unvalidated Hyprland version because AQ_DRM_DEVICES is explicitly configured"
        exit 0
      fi

      fail "Hyprland $hyprland_version is not in the validated split-GPU set ($validated_versions) and the target generation does not declare AQ_DRM_DEVICES. This is the exact shape of the regression that produced Aquamarine 'no matching devices found' and software rendering on Apple Silicon."
    '';
  };

  check = pkgs.runCommand "hyprland-gpu-preflight-check" { } ''
    set -euo pipefail
    ${preflight}/bin/hyprland-gpu-preflight
    mkdir -p "$out"
    echo ok > "$out/result"
  '';
in
{
  package = preflight;
  inherit check;
}
