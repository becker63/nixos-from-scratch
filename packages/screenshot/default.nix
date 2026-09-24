# screenshot: tofi-driven grim/slurp picker (fullscreen / region / region to
# clipboard). tofi, grim, slurp, and wl-clipboard resolve from the invoking
# user's PATH at runtime; they are provided by the system and HM package
# layers, matching how this script ran before its extraction.
{
  writeShellScriptBin,
}:
writeShellScriptBin "screenshot" ''
  #!/usr/bin/env bash

  mkdir -p "$HOME/Pictures"
  FILE="$HOME/Pictures/$(date +'%Y-%m-%d_%H-%M-%S').png"

  CHOICE=$(printf "Fullscreen\nRegion\nRegion → Clipboard\n" | tofi)

  case "$CHOICE" in
    "Fullscreen")
      grim "$FILE"
      ;;
    "Region")
      grim -g "$(slurp)" "$FILE"
      ;;
    "Region → Clipboard")
      grim -g "$(slurp)" - | wl-copy
      ;;
  esac
''
