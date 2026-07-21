{ pkgs, sourceRoot }:

let
  inherit (pkgs) lib;

  mockEww = pkgs.writeShellScriptBin "eww" ''
    set -euo pipefail

    {
      printf 'eww'
      for argument in "$@"; do
        printf '\t%s' "$argument"
      done
      printf '\n'
    } >> "$MOCK_LOG"

    if [ "$#" -gt 0 ] && [ "$1" = "active-windows" ]; then
      if [ -f "$MOCK_ACTIVE_WINDOWS_FILE" ]; then
        ${pkgs.coreutils}/bin/cat "$MOCK_ACTIVE_WINDOWS_FILE"
      fi
    fi
  '';

  mockWpctl = pkgs.writeShellScriptBin "wpctl" ''
    set -euo pipefail

    {
      printf 'wpctl'
      for argument in "$@"; do
        printf '\t%s' "$argument"
      done
      printf '\n'
    } >> "$MOCK_LOG"

    if [ "$#" -gt 0 ] && [ "$1" = "get-volume" ]; then
      printf 'Volume: 0.55\n'
    fi
  '';

  mockSystemctl = pkgs.writeShellScriptBin "systemctl" ''
    set -euo pipefail

    {
      printf 'systemctl'
      for argument in "$@"; do
        printf '\t%s' "$argument"
      done
      printf '\n'
    } >> "$MOCK_LOG"

    # Every worker named by a fixture is considered live. Fixtures that want a
    # new worker simply omit the worker file and never reach this command.
    exit 0
  '';

  mockSystemdRun = pkgs.writeShellScriptBin "systemd-run" ''
    set -euo pipefail

    {
      printf 'systemd-run'
      for argument in "$@"; do
        printf '\t%s' "$argument"
      done
      printf '\n'
    } >> "$MOCK_LOG"
  '';

  mockDate = pkgs.writeShellScriptBin "date" ''
    set -euo pipefail

    case "$1" in
      +%s%3N)
        printf '%s\n' "$MOCK_NOW_MS"
        ;;
      +%s%N)
        printf '%s\n' "$MOCK_NOW_NS"
        ;;
      *)
        printf 'unexpected date invocation: %s\n' "$*" >&2
        exit 2
        ;;
    esac
  '';

  mockChargeStatus = pkgs.writeShellScriptBin "charge-status" ''
    set -euo pipefail

    {
      printf 'charge-status'
      for argument in "$@"; do
        printf '\t%s' "$argument"
      done
      printf '\n'
    } >> "$MOCK_LOG"

    case "$1" in
      --fastfetch-status)
        printf 'Discharging · 73%% · 2:10 remaining\n'
        ;;
      --fastfetch-rate)
        printf '8.4 W\n'
        ;;
      --fastfetch-electrical)
        printf '11.7 V · 0.72 A\n'
        ;;
      *)
        printf 'unexpected charge-status invocation: %s\n' "$*" >&2
        exit 2
        ;;
    esac
  '';

  mockBrightnessctl = pkgs.writeShellScriptBin "brightnessctl" ''
    set -euo pipefail

    {
      printf 'brightnessctl'
      for argument in "$@"; do
        printf '\t%s' "$argument"
      done
      printf '\n'
    } >> "$MOCK_LOG"

    for argument in "$@"; do
      if [ "$argument" = "info" ]; then
        printf 'kbd_backlight,leds,1,42%%,100\n'
        exit 0
      fi
    done
  '';

  mockPath = lib.makeBinPath [
    mockEww
    mockWpctl
    mockSystemctl
    mockSystemdRun
    mockDate
    mockChargeStatus
    mockBrightnessctl
  ];

  contract = pkgs.writeShellApplication {
    name = "desktop-osd-contract";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gawk
      gnugrep
      gnused
      python3
      util-linux
    ];
    text = ''
      set -euo pipefail

      source_root='${sourceRoot}'

      if [ "$#" -gt 0 ]; then
        if [ "$#" -ne 2 ] || [ "$1" != "--source-root" ]; then
          echo "usage: desktop-osd-contract [--source-root PATH]" >&2
          exit 2
        fi
        source_root="$2"
      fi

      eww_file="$source_root/config/eww/eww.yuck"
      hypr_file="$source_root/config/hypr/hyprland.conf"
      power_script="$source_root/config/eww/scripts/power-osd"
      volume_script="$source_root/config/eww/scripts/volume-osd"
      keyboard_script="$source_root/config/eww/scripts/keyboard-backlight"
      mock_path='${mockPath}'
      bash_bin='${pkgs.bash}/bin/bash'

      fail() {
        echo "FAIL: $*" >&2
        exit 1
      }

      for required_file in \
        "$eww_file" \
        "$hypr_file" \
        "$power_script" \
        "$volume_script" \
        "$keyboard_script"
      do
        [ -f "$required_file" ] || fail "missing desktop OSD source: $required_file"
      done

      # Eww geometry and callbacks are declarative, so inspect their complete
      # balanced forms rather than relying on line numbers or formatting.
      export DESKTOP_OSD_EWW_FILE="$eww_file"
      export DESKTOP_OSD_HYPR_FILE="$hypr_file"
      python3 <<'PY'
      import os
      import pathlib
      import re
      import sys

      eww_path = pathlib.Path(os.environ["DESKTOP_OSD_EWW_FILE"])
      hypr_path = pathlib.Path(os.environ["DESKTOP_OSD_HYPR_FILE"])
      eww = eww_path.read_text(encoding="utf-8")
      hypr = hypr_path.read_text(encoding="utf-8")
      failures = []


      def require(condition, message):
          if not condition:
              failures.append(message)


      def balanced_form(source, form_kind, name):
          match = re.search(
              rf"\({re.escape(form_kind)}\s+{re.escape(name)}\b", source
          )
          if match is None:
              failures.append(f"missing ({form_kind} {name} ...) declaration")
              return ""

          depth = 0
          quoted = False
          escaped = False
          for index in range(match.start(), len(source)):
              character = source[index]
              if quoted:
                  if escaped:
                      escaped = False
                  elif character == "\\":
                      escaped = True
                  elif character == '"':
                      quoted = False
                  continue

              if character == '"':
                  quoted = True
              elif character == "(":
                  depth += 1
              elif character == ")":
                  depth -= 1
                  if depth == 0:
                      return source[match.start() : index + 1]

          failures.append(f"unterminated ({form_kind} {name} ...) declaration")
          return ""


      windows = {
          name: balanced_form(eww, "defwindow", name)
          for name in ("volume", "power", "power_hotspot", "power_confirm")
      }

      for name, form in windows.items():
          require(
              re.search(r':anchor\s+"top center"', form) is not None,
              f"{name} must remain anchored at the top center",
          )

      for name in ("volume", "power"):
          require(
              re.search(r':width\s+"420px"', windows[name]) is not None,
              f"{name} must remain 420px wide",
          )

      require(
          re.search(r':width\s+"420px"', windows["power_hotspot"]) is not None,
          "the power hotspot must cover the full 420px OSD width",
      )

      hotspot = balanced_form(eww, "defwidget", "power_hotspot_widget")
      require(
          re.search(r':onhover\s+"[^"]*power-osd\s+show[^"]*"', hotspot)
          is not None,
          "hovering the top-center hotspot must invoke power-osd show",
      )

      keyboard = balanced_form(eww, "defwidget", "keyboard_light")
      require(
          re.search(
              r':onchange\s+"[^"]*keyboard-backlight\s+set\s+\{\}'
              r'\s+&&\s+[^"]*power-osd\s+keepalive[^"]*"',
              keyboard,
          )
          is not None,
          "the keyboard-brightness scale must set brightness and keep power OSD alive",
      )

      binding_lines = []
      media_binding_lines = []
      for number, line in enumerate(hypr.splitlines(), start=1):
          stripped = line.strip()
          if not re.match(r"bind[a-z]*\s*=", stripped, flags=re.IGNORECASE):
              continue
          binding_lines.append((number, stripped))
          if "xf86" in stripped.lower() or re.search(
              r"(?:^|,)\s*f\d+\s*,", stripped, flags=re.IGNORECASE
          ):
              media_binding_lines.append((number, stripped))

          command = stripped.split("=", 1)[1]
          if re.search(r"\b(?:suspend|hibernate)\b", command, flags=re.IGNORECASE):
              failures.append(
                  f"Hyprland binding on line {number} can suspend or hibernate: {stripped}"
              )

      require(binding_lines, "Hyprland config contains no parsed bindings")
      require(media_binding_lines, "Hyprland config contains no Fn/media-key bindings")
      require(
          any(
              "xf86launcha" in line.lower() and "power-osd" in line
              for _, line in media_binding_lines
          ),
          "the Apple keyboard power-pane key must continue to open power-osd",
      )

      if failures:
          for failure in failures:
              print(f"FAIL: {failure}", file=sys.stderr)
          raise SystemExit(1)

      print("PASS: Eww geometry, hover controls, and Hyprland key safety")
      PY

      temp_root="$(mktemp -d)"
      cleanup() {
        chmod -R u+w "$temp_root" 2>/dev/null || true
        rm -rf "$temp_root"
      }
      trap cleanup EXIT

      start_case() {
        case_dir="$temp_root/$1"
        case_runtime="$case_dir/runtime"
        case_log="$case_dir/calls.log"
        case_windows="$case_dir/active-windows"
        mkdir -p "$case_runtime"
        : > "$case_log"
        : > "$case_windows"
      }

      prepare_worker() {
        worker_kind="$1"
        worker_dir="$case_runtime/minimal-osd-$UID"
        mkdir -p "$worker_dir"
        printf 'fixture-worker.service\n' > "$worker_dir/$worker_kind.worker"
      }

      run_script() {
        script="$1"
        shift
        PATH="$mock_path:$PATH" \
          XDG_RUNTIME_DIR="$case_runtime" \
          MOCK_LOG="$case_log" \
          MOCK_ACTIVE_WINDOWS_FILE="$case_windows" \
          MOCK_NOW_MS=100000 \
          MOCK_NOW_NS=100000000000 \
          "$bash_bin" "$script" "$@"
      }

      assert_equal() {
        expected="$1"
        actual="$2"
        description="$3"
        [ "$actual" = "$expected" ] \
          || fail "$description (expected '$expected', got '$actual')"
      }

      assert_log_contains() {
        pattern="$1"
        description="$2"
        grep -F -- "$pattern" "$case_log" >/dev/null \
          || fail "$description; missing call '$pattern'"
      }

      assert_log_excludes() {
        pattern="$1"
        description="$2"
        if grep -F -- "$pattern" "$case_log" >/dev/null; then
          fail "$description; unexpected call '$pattern'"
        fi
      }

      deadline_value() {
        deadline_kind="$1"
        cat "$case_runtime/minimal-osd-$UID/$deadline_kind.deadline"
      }

      # Repeated volume keys must update data and refresh the deadline in place.
      # Closing/reopening the window here is the flicker regression this guards.
      start_case volume-already-open
      printf '%s\n' 'volume: volume' 'power: power' > "$case_windows"
      prepare_worker volume
      run_script "$volume_script" up
      assert_log_contains $'wpctl\tset-mute\t@DEFAULT_AUDIO_SINK@\t0' \
        "volume-up must unmute the sink"
      assert_log_contains $'wpctl\tset-volume\t-l\t2.0\t@DEFAULT_AUDIO_SINK@\t5%+' \
        "volume-up must adjust the sink"
      assert_log_contains $'eww\tupdate\tvolume_percent=55\tvolume_muted=false\tvolume_kind=vol' \
        "an open volume window must receive fresh values"
      assert_log_excludes $'eww\tclose\tvolume' \
        "an ordinary volume press must not close an open window"
      assert_log_excludes $'eww\topen\tvolume' \
        "an ordinary volume press must not reopen an open window"
      assert_equal 101400 "$(deadline_value volume)" \
        "the volume pane timeout must remain 1400ms"

      # Opening volume chooses an offset below whichever power surface is live.
      start_case volume-under-power
      printf '%s\n' 'power: power' > "$case_windows"
      prepare_worker volume
      run_script "$volume_script" show
      assert_log_contains $'eww\topen\tvolume\t--arg\toffset=202px' \
        "volume must stack below the full power pane"

      start_case volume-under-confirmation
      printf '%s\n' 'power_confirm: power_confirm' > "$case_windows"
      prepare_worker volume
      run_script "$volume_script" show
      assert_log_contains $'eww\topen\tvolume\t--arg\toffset=70px' \
        "volume must stack below the power confirmation pane"

      start_case volume-standalone
      prepare_worker volume
      run_script "$volume_script" show
      assert_log_contains $'eww\topen\tvolume\t--arg\toffset=14px' \
        "standalone volume must remain at the top-center inset"

      # Hover/show and slider keepalive are timer refreshes while power is open;
      # neither path may toggle the pane or re-query battery state.
      for refresh_mode in show keepalive; do
        start_case "power-refresh-$refresh_mode"
        printf '%s\n' 'power: power' > "$case_windows"
        prepare_worker power
        run_script "$power_script" "$refresh_mode"
        assert_equal 104000 "$(deadline_value power)" \
          "power $refresh_mode must refresh the 4000ms deadline"
        assert_log_excludes $'eww\topen\tpower' \
          "power $refresh_mode must not reopen an open pane"
        assert_log_excludes $'eww\tclose\tpower' \
          "power $refresh_mode must not close an open pane"
        assert_log_excludes $'charge-status\t' \
          "power $refresh_mode must only refresh the timer"
        assert_log_excludes $'systemd-run\t' \
          "power $refresh_mode must reuse its live hide worker"
      done

      # The command wired to hotspot hover must also open a closed pane and arm
      # one hide worker, proving the declaration and script agree end-to-end.
      start_case hotspot-show-closed-power
      run_script "$power_script" show
      assert_log_contains $'eww\topen\tpower' \
        "power-osd show must open a closed power pane"
      assert_log_contains $'capacity=73' \
        "power-osd show must derive the displayed battery capacity"
      assert_log_contains $'state=battery' \
        "power-osd show must derive the displayed battery state"
      assert_log_contains $'systemd-run\t--user\t--quiet\t--collect' \
        "a newly opened power pane must arm its hide worker"
      assert_equal 104000 "$(deadline_value power)" \
        "a newly opened power pane must use the 4000ms timeout"

      # Exercise the exact helper invoked by the Eww mouse scale. This checks
      # the LED class/device contract and its numeric normalization.
      start_case keyboard-backlight
      run_script "$keyboard_script" set 47.9
      assert_log_contains $'brightnessctl\t--quiet\t--class\tleds\t--device\tkbd_backlight\t--min-value=0\tset\t47%' \
        "keyboard-brightness mouse values must target kbd_backlight"
      run_script "$keyboard_script" set 115
      assert_log_contains $'brightnessctl\t--quiet\t--class\tleds\t--device\tkbd_backlight\t--min-value=0\tset\t100%' \
        "keyboard brightness must clamp mouse input to 100 percent"
      keyboard_value="$(run_script "$keyboard_script" get)"
      assert_equal 42 "$keyboard_value" \
        "keyboard brightness polling must parse brightnessctl machine output"

      echo "PASS: desktop OSD scripts preserve stacking, timeout, refresh, and keyboard controls"
    '';
  };

  check = pkgs.runCommand "desktop-osd-contract-check" { } ''
    set -euo pipefail
    ${contract}/bin/desktop-osd-contract --source-root '${sourceRoot}'
    mkdir -p "$out"
    echo ok > "$out/result"
  '';
in
{
  package = contract;
  inherit check;
}
