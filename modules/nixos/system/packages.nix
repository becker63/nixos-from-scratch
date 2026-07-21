{ pkgs, ... }:

let
  chargeStatus = pkgs.writeShellScriptBin "charge-status" ''
    #!/usr/bin/env bash
    set -euo pipefail

    mode="''${1:-full}"

    battery=""
    ac_online=0

    for supply in /sys/class/power_supply/*; do
      [ -r "$supply/type" ] || continue
      case "$(<"$supply/type")" in
        Battery) battery="$supply" ;;
        Mains|USB)
          if [ -r "$supply/online" ] && [ "$(<"$supply/online")" = "1" ]; then
            ac_online=1
          fi
          ;;
      esac
    done

    if [ -z "$battery" ]; then
      printf 'No battery detected\n'
      exit 0
    fi

    read_value() {
      local field="$1"
      local value
      if [ -r "$battery/$field" ]; then
        IFS= read -r value < "$battery/$field"
        printf '%s\n' "$value"
      else
        printf '0\n'
      fi
    }

    absolute() {
      local value="$1"
      if [ "$value" -lt 0 ]; then
        printf '%d\n' "$((-value))"
      else
        printf '%d\n' "$value"
      fi
    }

    # Present a micro-unit value as a decimal value in the supplied unit.
    # For example, 3345000 µW at a scale of 100000 becomes 3.3 W.
    format_tenths() {
      local tenths=$(( $1 / $2 ))
      printf '%d.%d' "$((tenths / 10))" "$((tenths % 10))"
    }

    format_duration() {
      local seconds="$1"
      if [ "$seconds" -le 0 ]; then
        printf 'estimating'
      else
        printf '%dh%02dm' "$((seconds / 3600))" "$(((seconds % 3600) / 60))"
      fi
    }

    status="$(read_value status)"
    capacity="$(read_value capacity)"
    power="$(absolute "$(read_value power_now)")"
    current="$(absolute "$(read_value current_now)")"
    voltage="$(absolute "$(read_value voltage_now)")"
    energy_now="$(read_value energy_now)"
    energy_full="$(read_value energy_full)"

    power_w="$(format_tenths "$power" 100000)"
    current_a="$(format_tenths "$current" 100000)"
    voltage_v="$(format_tenths "$voltage" 100000)"
    energy_wh="$(format_tenths "$energy_now" 100000)"
    energy_full_wh="$(format_tenths "$energy_full" 100000)"

    if [ "$status" = "Charging" ]; then
      remaining=$((energy_full - energy_now))
      if [ "$power" -gt 0 ] && [ "$remaining" -gt 0 ]; then
        eta=$((60 * 60 * remaining / power))
      else
        eta="$(read_value time_to_full_now)"
      fi
      case "$mode" in
        --fastfetch-status)
          printf '%s · %s%% · %s\n' "$status" "$capacity" \
            "$([ "$ac_online" = 1 ] && printf 'AC online' || printf 'external power not detected')"
          ;;
        --fastfetch-rate)
          printf '%s W into battery · ~%s to full\n' "$power_w" "$(format_duration "$eta")"
          ;;
        --fastfetch-electrical)
          printf '%s A @ %s V · %s / %s Wh\n' \
            "$current_a" "$voltage_v" "$energy_wh" "$energy_full_wh"
          ;;
        *)
          printf '⚡ %s · %s%% · %s W into battery · %s · %s A @ %s V · ~%s to full\n' \
            "$status" "$capacity" "$power_w" \
            "$([ "$ac_online" = 1 ] && printf 'AC online' || printf 'external power not detected')" \
            "$current_a" "$voltage_v" "$(format_duration "$eta")"
          ;;
      esac
    elif [ "$status" = "Discharging" ]; then
      eta="$(read_value time_to_empty_now)"
      case "$mode" in
        --fastfetch-status)
          printf '%s · %s%%\n' "$status" "$capacity"
          ;;
        --fastfetch-rate)
          printf '%s W draw · ~%s remaining\n' "$power_w" "$(format_duration "$eta")"
          ;;
        --fastfetch-electrical)
          printf '%s A @ %s V · %s / %s Wh\n' \
            "$current_a" "$voltage_v" "$energy_wh" "$energy_full_wh"
          ;;
        *)
          printf '󰂄 %s · %s%% · %s W draw · %s A @ %s V · ~%s remaining\n' \
            "$status" "$capacity" "$power_w" "$current_a" "$voltage_v" "$(format_duration "$eta")"
          ;;
      esac
    else
      case "$mode" in
        --fastfetch-status)
          printf '%s · %s%% · %s\n' "$status" "$capacity" \
            "$([ "$ac_online" = 1 ] && printf 'AC online' || printf 'on battery')"
          ;;
        --fastfetch-rate)
          printf '%s W\n' "$power_w"
          ;;
        --fastfetch-electrical)
          printf '%s A @ %s V · %s / %s Wh\n' \
            "$current_a" "$voltage_v" "$energy_wh" "$energy_full_wh"
          ;;
        *)
          printf '󰁹 %s · %s%% · %s W · %s\n' \
            "$status" "$capacity" "$power_w" \
            "$([ "$ac_online" = 1 ] && printf 'AC online' || printf 'on battery')"
          ;;
      esac
    fi
  '';

  chargeMonitor = pkgs.writeShellScriptBin "charge-monitor" ''
    #!/usr/bin/env bash
    set -euo pipefail

    interval="''${1:-2}"
    while true; do
      clear
      printf '\033[1;36mCharging monitor\033[0m  (refreshing every %ss; Ctrl-C to exit)\n\n' "$interval"
      ${chargeStatus}/bin/charge-status
      sleep "$interval"
    done
  '';
in
{
  environment.systemPackages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.zed-mono
    codex
    lorri
    fastfetch
    chargeStatus
    chargeMonitor
    antigravity-fhs
    wget
    git
    iproute2
    mesa-demos
    nh
    buildah
    killall
    file
    distrobox
    distrobox-tui
    boxbuddy
    xonsh
    tree
    starship
    unzip
    nix-direnv
    pavucontrol
    gnome-keyring

    grim
    slurp
    wl-clipboard

    qt6.qtwayland
    qt5.qtwayland
    gdm
    gnome-session
    gnome-shell

    (writeShellScriptBin "screenshot" ''
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
    '')

    (writeShellScriptBin "moonlight-asahi" ''
      # Wayland + Asahi GPU environment
      export QT_QPA_PLATFORM=wayland-egl
      export QT_QPA_PLATFORMTHEME=qt5ct
      export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
      export MOZ_ENABLE_WAYLAND=1
      export NIXOS_OZONE_WL=1
      export MESA_LOADER_DRIVER_OVERRIDE=asahi
      export LIBVA_DRIVER_NAME=asahi
      export VDPAU_DRIVER=va_gl
      export XDG_SESSION_TYPE=wayland
      export GDK_BACKEND=wayland

      # Fix Moonlight audio on Asahi / PipeWire
      export SDL_AUDIODRIVER=pulseaudio

      DEFAULT_FLAGS=(
        --no-audio-on-host
        --audio-config stereo
      )

      # If no action supplied, start GUI normally
      if [ $# -eq 0 ]; then
        exec ${pkgs.moonlight-qt}/bin/moonlight "''${DEFAULT_FLAGS[@]}"
      else
        exec ${pkgs.moonlight-qt}/bin/moonlight "''${DEFAULT_FLAGS[@]}" "$@"
      fi
    '')

    bat

    bluez
    bluez-tools
    blueman
    bluetuith

    ncdu
    tailscale
    age
    ssh-to-age
    sops
    jq
    nmap
    arp-scan
    usbutils
    gptfdisk
    parted
    pv
    nixos-anywhere
    nautilus
  ];
}
