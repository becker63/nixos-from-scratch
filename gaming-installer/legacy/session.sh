# Legacy first-ISO wrapper, retained to diagnose the already installed machine.
# New configurations use Jovian's upstream session manager instead.
state="${XDG_RUNTIME_DIR:?}/gaming-session"
mkdir -p "$state"
chmod 700 "$state"
printf '%s\n' "$$" > "$state/controller"
child=""
requested=false
switch_mode() {
  requested=true
  if [[ -n "$child" ]]; then
    kill -TERM -- "-$child" 2>/dev/null || true
  fi
}
cleanup() {
  if [[ -n "$child" ]]; then kill -TERM -- "-$child" 2>/dev/null || true; fi
  rm -f "$state/controller" "$state/next"
}
trap switch_mode USR1
trap cleanup EXIT
trap 'exit 0' TERM INT
mode=steam
while true; do
  requested=false
  rm -f "$state/next"
  case "$mode" in
    steam)
      export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=gamescope
      # Keep desktop-specific Qt/GTK Wayland overrides out of Steam's runtime.
      setsid dbus-run-session -- @GAMESCOPE@ --steam -- @STEAM@ -tenfoot -pipewire-dmabuf &
      ;;
    desktop)
      export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=Hyprland
      setsid dbus-run-session -- @HYPRLAND@ &
      ;;
    terminal)
      printf '\nRepair menu: steam / desktop / shell (exit the shell to return here)\n'
      read -r choice || choice=steam
      case "$choice" in
        steam|desktop) mode="$choice" ;;
        shell) bash -il || true ;;
        *) mode=terminal ;;
      esac
      if [[ -r "$state/next" ]]; then mode="$(<"$state/next")"; fi
      continue ;;
  esac
  child=$!
  status=0
  wait "$child" || status=$?
  if [[ "$requested" == true ]]; then
    wait "$child" 2>/dev/null || true
  fi
  child=""
  if [[ -r "$state/next" ]]; then
    mode="$(<"$state/next")"
    case "$mode" in steam|desktop|terminal) ;; *) mode=terminal ;; esac
  elif [[ "$status" -ne 0 ]]; then
    printf '\nSession exited with status %s. Opening repair terminal.\n' "$status"
    mode=terminal
  elif [[ "$mode" == steam ]]; then
    # Steam's Exit Steam action opens your familiar desktop.
    mode=desktop
  else
    mode=steam
  fi
done
