#!/usr/bin/env bash
# Exercise the legacy session transitions using stubs, without a GPU or changing services.
set -euo pipefail
test_root="$(mktemp -d /tmp/gaming-session-test.XXXXXXXX)"
trap 'rm -rf -- "$test_root"' EXIT
rendered="$(sed -e 's|@GAMESCOPE@|stub-steam|g' -e 's|@STEAM@|stub-client|g' -e 's|@HYPRLAND@|stub-desktop|g' "$(dirname "$0")/session.sh")"
session_stub() {
  # Arguments are: dbus-run-session -- stub-program ...
  local program="$3"
  case "$program" in
    stub-steam)
      printf 'steam\n' >> "$TEST_EVENTS"
      if [[ "$TEST_CASE" == failure ]]; then return 7; fi
      if [[ "$TEST_CASE" == requested ]]; then
        printf 'desktop\n' > "$XDG_RUNTIME_DIR/gaming-session/next"
        kill -USR1 "$(<"$XDG_RUNTIME_DIR/gaming-session/controller")"
        sleep 5
      fi
      if [[ "$TEST_CASE" == roundtrip ]] && [[ $(wc -l < "$TEST_EVENTS") -eq 3 ]]; then
        kill -TERM "$(<"$XDG_RUNTIME_DIR/gaming-session/controller")"
      fi
      ;;
    stub-desktop)
      printf 'desktop\n' >> "$TEST_EVENTS"
      if [[ "$TEST_CASE" != roundtrip ]]; then
        kill -TERM "$(<"$XDG_RUNTIME_DIR/gaming-session/controller")"
      fi
      ;;
  esac
}
# Preserve real setsid so cleanup/signals stay within the test's process groups.
setsid() { command setsid bash -c 'session_stub "$@"' -- "$@"; }
export -f setsid session_stub
for scenario in normal failure roundtrip requested; do
  export TEST_CASE="$scenario" TEST_EVENTS="$test_root/$scenario.events"
  export XDG_RUNTIME_DIR="$test_root/$scenario.runtime"
  mkdir -p "$XDG_RUNTIME_DIR"
  printf 'desktop\n' | timeout 5 bash -euo pipefail -c "$rendered" > "$test_root/$scenario.output" 2>&1
  observed="$(paste -sd, "$TEST_EVENTS")"
  expected=steam,desktop
  if [[ "$scenario" == roundtrip ]]; then expected=steam,desktop,steam; fi
  [[ "$observed" == "$expected" ]] || { echo "$scenario: expected $expected, got $observed" >&2; exit 1; }
  if [[ "$scenario" == failure ]]; then grep -q 'status 7' "$test_root/$scenario.output"; fi
  [[ ! -e "$XDG_RUNTIME_DIR/gaming-session/controller" ]]
  printf 'PASS %s: %s\n' "$scenario" "$observed"
done
