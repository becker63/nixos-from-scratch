# moonlight-asahi: Moonlight Qt wrapper for game streaming on Asahi.
# Only the exports that differ from or extend environment.sessionVariables
# live here (QT_QPA_PLATFORM=wayland-egl overrides the session's "wayland";
# the qt5ct theme, window-decoration flag, and SDL audio driver are
# wrapper-specific). Variables that duplicated the session defaults exactly
# were trimmed — see desktop.nix and nodes/nixos-btw/configuration.nix.
{
  writeShellScriptBin,
  moonlight-qt,
}:
writeShellScriptBin "moonlight-asahi" ''
  # Wayland + Asahi GPU environment
  export QT_QPA_PLATFORM=wayland-egl
  export QT_QPA_PLATFORMTHEME=qt5ct
  export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

  # Fix Moonlight audio on Asahi / PipeWire
  export SDL_AUDIODRIVER=pulseaudio

  DEFAULT_FLAGS=(
    --no-audio-on-host
    --audio-config stereo
  )

  # If no action supplied, start GUI normally
  if [ $# -eq 0 ]; then
    exec ${moonlight-qt}/bin/moonlight "''${DEFAULT_FLAGS[@]}"
  else
    exec ${moonlight-qt}/bin/moonlight "''${DEFAULT_FLAGS[@]}" "$@"
  fi
''
