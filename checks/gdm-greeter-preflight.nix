{ pkgs, systemBuild }:
let
  preflight = pkgs.writeShellApplication {
    name = "gdm-greeter-preflight";
    runtimeInputs = with pkgs; [
      binutils
      coreutils
      gnugrep
      gnused
      gawk
      shadow
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

      system_build='${systemBuild}'
      unit="$system_build/etc/systemd/system/display-manager.service"

      [ -f "$unit" ] || fail "display-manager.service not found in $system_build"

      display_manager_xdg_data_dirs="$(sed -n 's/^Environment="XDG_DATA_DIRS=\([^"]*\)"/\1/p' "$unit")"
      [ -n "$display_manager_xdg_data_dirs" ] || fail "display-manager.service does not export XDG_DATA_DIRS"

      display_manager_path="$(sed -n 's/^Environment="PATH=\([^"]*\)"/\1/p' "$unit")"
      [ -n "$display_manager_path" ] || fail "display-manager.service does not export PATH"

      locale_archive="$(sed -n 's/^Environment="LOCALE_ARCHIVE=\([^"]*\)"/\1/p' "$unit")"

      gdm_share=""
      while IFS= read -r data_dir; do
        if [ -f "$data_dir/gnome-session/sessions/gnome-login.session" ]; then
          gdm_share="$data_dir"
          break
        fi
      done < <(printf '%s\n' "$display_manager_xdg_data_dirs" | tr ':' '\n')

      [ -n "$gdm_share" ] || fail "display-manager.service does not expose a gdm share containing gnome-login.session"

      session_file="$gdm_share/gnome-session/sessions/gnome-login.session"
      note "display-manager XDG_DATA_DIRS: $display_manager_xdg_data_dirs"
      note "gdm greeter session file: $session_file"

      gnome_session_bin="$(PATH="$display_manager_path" command -v gnome-session || true)"
      [ -x "$gnome_session_bin" ] || fail "gnome-session is not resolvable from display-manager PATH"

      session_service="''${gnome_session_bin%/bin/gnome-session}/libexec/gnome-session-service"
      [ -x "$session_service" ] || fail "gnome-session-service not found at $session_service"

      wrapper_xdg_data_dirs="$(
        strings "$gnome_session_bin" \
          | sed -n "s/.*--prefix 'XDG_DATA_DIRS' ':' '\\([^']*\\)'.*/\\1/p; s/.*--suffix 'XDG_DATA_DIRS' ':' '\\([^']*\\)'.*/\\1/p" \
          | awk 'BEGIN { ORS = ":" } { print $0 }'
      )"
      wrapper_xdg_data_dirs="''${wrapper_xdg_data_dirs%:}"

      [ -n "$wrapper_xdg_data_dirs" ] || fail "could not extract wrapped gnome-session XDG_DATA_DIRS"
      note "wrapped gnome-session XDG_DATA_DIRS: $wrapper_xdg_data_dirs"

      simulated_xdg_data_dirs="$system_build/sw/share"
      if [ -n "$wrapper_xdg_data_dirs" ]; then
        simulated_xdg_data_dirs="$simulated_xdg_data_dirs:$wrapper_xdg_data_dirs"
      fi
      note "simulated greeter XDG_DATA_DIRS: $simulated_xdg_data_dirs"

      tmpdir="$(mktemp -d)"
      cleanup() {
        chmod -R u+w "$tmpdir" 2>/dev/null || true
        rm -rf "$tmpdir"
      }
      trap cleanup EXIT

      export HOME="$tmpdir/home"
      export XDG_CONFIG_HOME="$HOME/.config"
      export XDG_CACHE_HOME="$HOME/.cache"
      export XDG_STATE_HOME="$HOME/.local/state"
      export XDG_RUNTIME_DIR="$tmpdir/runtime"

      mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
      chmod 700 "$XDG_RUNTIME_DIR"

      output="$tmpdir/gnome-session-service.log"

      set +e
      HOME="$HOME" \
        USER="gdm-greeter" \
        LOGNAME="gdm-greeter" \
        SHELL="${pkgs.shadow}/bin/nologin" \
        XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        XDG_DATA_DIRS="$simulated_xdg_data_dirs" \
        LOCALE_ARCHIVE="$locale_archive" \
        G_MESSAGES_DEBUG="all" \
        ${pkgs.coreutils}/bin/timeout 5s \
        "$session_service" --session=gnome-login >"$output" 2>&1
      status=$?
      set -e

      case "$status" in
        0|1|124)
          ;;
        *)
          fail "gnome-session-service exited unexpectedly with status $status"
          ;;
      esac

      grep -F "Getting session 'gnome-login'" "$output" >/dev/null \
        || fail "test did not reach gnome-login session resolution"

      if grep -F "Failed to fill session" "$output" >/dev/null; then
        echo >&2
        echo "----- gnome-session-service output -----" >&2
        cat "$output" >&2
        echo "---------------------------------------" >&2
        fail "gnome-session-service could not resolve gnome-login.session during the greeter handoff"
      fi

      grep -F "$system_build/sw/share/gnome-session/sessions/gnome-login.session" "$output" >/dev/null \
        || fail "session-service never consulted the built system profile for gnome-login.session"

      note "gnome-session-service resolved gnome-login.session successfully"
    '';
  };

  check = pkgs.runCommand "gdm-greeter-preflight-check" {
    nativeBuildInputs = with pkgs; [
      binutils
      coreutils
      gnugrep
      gnused
      gawk
    ];
  } ''
    set -euo pipefail

    unit='${systemBuild}/etc/systemd/system/display-manager.service'
    display_manager_xdg_data_dirs="$(sed -n 's/^Environment="XDG_DATA_DIRS=\([^"]*\)"/\1/p' "$unit")"
    display_manager_path="$(sed -n 's/^Environment="PATH=\([^"]*\)"/\1/p' "$unit")"

    [ -n "$display_manager_xdg_data_dirs" ] || {
      echo "FAIL: display-manager.service does not export XDG_DATA_DIRS" >&2
      exit 1
    }

    [ -n "$display_manager_path" ] || {
      echo "FAIL: display-manager.service does not export PATH" >&2
      exit 1
    }

    gdm_share=""
    while IFS= read -r data_dir; do
      if [ -f "$data_dir/gnome-session/sessions/gnome-login.session" ]; then
        gdm_share="$data_dir"
        break
      fi
    done < <(printf '%s\n' "$display_manager_xdg_data_dirs" | tr ':' '\n')

    [ -n "$gdm_share" ] || {
      echo "FAIL: display-manager.service does not expose a gdm share containing gnome-login.session" >&2
      exit 1
    }

    system_session='${systemBuild}/sw/share/gnome-session/sessions/gnome-login.session'
    [ -f "$system_session" ] || {
      echo "FAIL: built system profile does not expose gnome-login.session under sw/share/gnome-session" >&2
      exit 1
    }

    systemd_dropin='${systemBuild}/sw/share/systemd/user/gnome-session@gnome-login.target.d/gnome-login.session.conf'
    [ -f "$systemd_dropin" ] || {
      echo "FAIL: built system profile does not expose the gnome-login systemd drop-in" >&2
      exit 1
    }

    gnome_session_bin="$(PATH="$display_manager_path" command -v gnome-session || true)"
    [ -x "$gnome_session_bin" ] || {
      echo "FAIL: gnome-session is not resolvable from display-manager PATH" >&2
      exit 1
    }

    wrapper_xdg_data_dirs="$(
      strings "$gnome_session_bin" \
        | sed -n "s/.*--prefix 'XDG_DATA_DIRS' ':' '\\([^']*\\)'.*/\\1/p; s/.*--suffix 'XDG_DATA_DIRS' ':' '\\([^']*\\)'.*/\\1/p" \
        | awk 'BEGIN { ORS = ":" } { print $0 }'
    )"
    wrapper_xdg_data_dirs="''${wrapper_xdg_data_dirs%:}"

    [ -n "$wrapper_xdg_data_dirs" ] || {
      echo "FAIL: could not extract wrapped gnome-session XDG_DATA_DIRS" >&2
      exit 1
    }

    mkdir -p "$out"
    echo "ok" > "$out/result"
  '';
in
{
  package = preflight;
  inherit check;
}
