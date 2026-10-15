{ pkgs }:

let
  fontConfig = pkgs.makeFontsConf {
    fontDirectories = [ pkgs.dejavu_fonts ];
  };
in
pkgs.runCommand "alacritty-copybuffer-check"
  {
    nativeBuildInputs = [
      pkgs.alacritty
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gzip
      pkgs.imagemagick
      pkgs.xwd
      pkgs.xclip
      pkgs.xorg-server
      pkgs.python3
    ];
  }
  ''
    set -euo pipefail

    fail() {
      echo "FAIL: $*" >&2
      exit 1
    }

    # Check the installed public contract, including the generated artifacts
    # which are easy to omit when adding an upstream-style Clap subcommand.
    alacritty msg --help > "$TMPDIR/msg-help"
    grep -F 'copy-buffer' "$TMPDIR/msg-help" >/dev/null \
      || fail "copy-buffer is absent from alacritty msg"
    grep -F 'gutter-event' "$TMPDIR/msg-help" >/dev/null \
      || fail "gutter-event is absent from alacritty msg"

    alacritty msg copy-buffer --help > "$TMPDIR/copy-buffer-help"
    grep -F 'Copy the complete primary screen and scrollback buffer' \
      "$TMPDIR/copy-buffer-help" >/dev/null \
      || fail "copy-buffer help does not describe full-buffer capture"
    grep -F -- '--clear' "$TMPDIR/copy-buffer-help" >/dev/null \
      || fail "copy-buffer does not expose --clear"
    grep -F -- '--window-id' "$TMPDIR/copy-buffer-help" >/dev/null \
      || fail "copy-buffer does not expose --window-id"

    alacritty msg gutter-event --help > "$TMPDIR/gutter-event-help"
    gutter_events='reset codex-start codex-stop reasoning search read edit tool test verify complete failed command-start command-pass command-fail campaign-launch candidate-start candidate-reject candidate-pass qualification-start qualified composition-start composition-pass wrench-start wrench-reject'
    for gutter_event in $gutter_events; do
      grep -Fw -- "$gutter_event" "$TMPDIR/gutter-event-help" >/dev/null \
        || fail "gutter-event help omits $gutter_event"
    done
    grep -F -- '--window-id' "$TMPDIR/gutter-event-help" >/dev/null \
      || fail "gutter-event does not expose --window-id"
    if alacritty msg gutter-event arbitrary-ui-text \
      > "$TMPDIR/invalid-gutter.stdout" 2> "$TMPDIR/invalid-gutter.stderr"
    then
      fail "gutter-event accepted a value outside its bounded vocabulary"
    fi

    gzip -dc '${pkgs.alacritty}/share/man/man1/alacritty-msg.1.gz' \
      > "$TMPDIR/alacritty-msg.1"
    # scdoc escapes command-name hyphens as `\\-` in newer Alacritty man
    # pages, while older versions emit them literally.
    grep -E 'copy\\?-buffer' "$TMPDIR/alacritty-msg.1" >/dev/null \
      || fail "the installed man page omits copy-buffer"
    grep -E '(\\-){2}clear|--clear' "$TMPDIR/alacritty-msg.1" >/dev/null \
      || fail "the installed man page omits --clear"
    grep -E 'gutter\\?-event' "$TMPDIR/alacritty-msg.1" >/dev/null \
      || fail "the installed man page omits gutter-event"

    for completion in \
      '${pkgs.alacritty}/share/bash-completion/completions/alacritty.bash' \
      '${pkgs.alacritty}/share/fish/vendor_completions.d/alacritty.fish' \
      '${pkgs.alacritty}/share/zsh/site-functions/_alacritty'
    do
      grep -F 'copy-buffer' "$completion" >/dev/null \
        || fail "copy-buffer is absent from $completion"
      grep -F 'gutter-event' "$completion" >/dev/null \
        || fail "gutter-event is absent from $completion"
    done

    # Exercise the real Alacritty event loop on a private X server. This never
    # reaches the user's compositor or clipboard. Xvfb is used instead of a
    # headless Wayland compositor because Wayland clipboard ownership requires
    # an input seat with focus, which a headless compositor cannot guarantee.
    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    export FONTCONFIG_FILE='${fontConfig}'
    export LIBGL_ALWAYS_SOFTWARE=1
    export LIBGL_DRIVERS_PATH='${pkgs.mesa}/lib/dri'
    export __EGL_VENDOR_LIBRARY_FILENAMES='${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json'
    export LD_LIBRARY_PATH='${pkgs.mesa}/lib:${pkgs.libglvnd}/lib'
    export DISPLAY=:99
    unset WAYLAND_DISPLAY

    mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"

    xvfb_pid=""
    alacritty_pid=""
    cleanup() {
      set +e
      if [ -n "$alacritty_pid" ]; then
        kill "$alacritty_pid" 2>/dev/null || true
        wait "$alacritty_pid" 2>/dev/null || true
      fi
      if [ -n "$xvfb_pid" ]; then
        kill "$xvfb_pid" 2>/dev/null || true
        wait "$xvfb_pid" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT

    Xvfb "$DISPLAY" -screen 0 800x600x24 -nolisten tcp -ac \
      > "$TMPDIR/xvfb.log" 2>&1 &
    xvfb_pid=$!

    for _ in $(seq 1 100); do
      [ -S /tmp/.X11-unix/X99 ] && break
      kill -0 "$xvfb_pid" 2>/dev/null \
        || fail "Xvfb exited before creating its display socket"
      sleep 0.05
    done
    [ -S /tmp/.X11-unix/X99 ] || fail "Xvfb display socket was not created"

    state="$TMPDIR/state"
    mkdir -p "$state"

    TEST_STATE="$state" alacritty \
      -o window.dimensions.columns=40 \
      -o window.dimensions.lines=10 \
      -o window.padding.x=70 \
      -o colors.primary.background='"#000000"' \
      -o colors.primary.foreground='"#cbd5e1"' \
      -e sh -c '
        printf "%s\n" "$ALACRITTY_SOCKET" > "$TEST_STATE/socket"
        printf "%s\n" "$ALACRITTY_WINDOW_ID" > "$TEST_STATE/window"
        printf "native-scrollback-marker\n"
        i=1
        while [ "$i" -le 40 ]; do
          printf "filler-%03d\n" "$i"
          i=$((i + 1))
        done
        printf "native-before-tail\n"
        # Paint unique cells at both advertised PTY edges for pixel geometry.
        printf "\033[s\033[1;1H\033[48;2;0;255;255m \033[0m\033[1;40H\033[48;2;255;0;255m \033[0m\033[u"
        sleep 0.2
        touch "$TEST_STATE/ready"
        while [ ! -e "$TEST_STATE/release" ]; do
          if [ -e "$TEST_STATE/repaint" ] && [ ! -e "$TEST_STATE/repaint-done" ]; then
            printf "\033[2K\r"
            touch "$TEST_STATE/repaint-done"
          fi
          sleep 0.02
        done
        printf "native-after\n"
        sleep 0.2
        touch "$TEST_STATE/after"
        while [ ! -e "$TEST_STATE/exit" ]; do sleep 0.02; done
      ' > "$TMPDIR/alacritty.stdout" 2> "$TMPDIR/alacritty.stderr" &
    alacritty_pid=$!

    for _ in $(seq 1 200); do
      [ -e "$state/ready" ] && break
      if ! kill -0 "$alacritty_pid" 2>/dev/null; then
        cat "$TMPDIR/alacritty.stderr" >&2
        fail "Alacritty exited before the capture fixture was ready"
      fi
      sleep 0.05
    done
    [ -e "$state/ready" ] || {
      cat "$TMPDIR/alacritty.stderr" >&2
      fail "Alacritty capture fixture timed out"
    }

    # The line-number gutter is rendered by Alacritty itself, so exercise the
    # final pixel output rather than merely checking for a source-level patch.
    # The private fixture deliberately reserves 70px: the fallback test font
    # is wider than the configured JetBrains Mono font used on the desktop.
    xwd -root -silent \
      | magick xwd:- -crop 220x220+0+0 -format '%k' info: \
      > "$TMPDIR/gutter-colors"
    [ "$(cat "$TMPDIR/gutter-colors")" -gt 1 ] \
      || fail "the Zed-style line-number gutter did not render pixels"

    # The wide, symmetric padding must not clip the final PTY column.
    xwd -id "$(cat "$state/window")" -silent \
      | magick xwd:- -format '%c' histogram:info:- > "$TMPDIR/right-edge-colors"
    grep -i '#FF00FF' "$TMPDIR/right-edge-colors" >/dev/null \
      || fail "the final PTY column is clipped by asymmetric gutter padding"

    socket_path="$(cat "$state/socket")"
    window_id="$(cat "$state/window")"
    [ -S "$socket_path" ] || fail "Alacritty did not expose its IPC socket"
    [ -n "$window_id" ] || fail "Alacritty did not export its window ID"

    if env -u ALACRITTY_WINDOW_ID \
      ALACRITTY_SOCKET="$socket_path" \
      alacritty msg gutter-event search \
      > "$TMPDIR/untargeted-gutter.stdout" 2> "$TMPDIR/untargeted-gutter.stderr"
    then
      fail "an untargeted gutter-event unexpectedly succeeded"
    fi
    grep -F 'requires --window-id or ALACRITTY_WINDOW_ID' \
      "$TMPDIR/untargeted-gutter.stderr" >/dev/null \
      || fail "an untargeted gutter event failed without the expected diagnostic"

    # Exercise every typed token through serde, the IPC socket, exact window
    # routing, and the positive acknowledgement path.
    for gutter_event in $gutter_events; do
      ALACRITTY_SOCKET="$socket_path" \
        ALACRITTY_WINDOW_ID="$window_id" \
        alacritty msg gutter-event "$gutter_event"
    done
    ALACRITTY_SOCKET="$socket_path" \
      ALACRITTY_WINDOW_ID="$window_id" \
      alacritty msg gutter-event reset

    xwd -root -silent \
      | magick xwd:- -crop 220x220+0+0 +repage -format '%#' info: \
      > "$TMPDIR/gutter-before"
    ALACRITTY_SOCKET="$socket_path" \
      ALACRITTY_WINDOW_ID="$window_id" \
      alacritty msg gutter-event campaign-launch
    sleep 0.15
    xwd -root -silent \
      | magick xwd:- -crop 220x220+0+0 +repage -format '%#' info: \
      > "$TMPDIR/gutter-after"
    [ "$(cat "$TMPDIR/gutter-before")" = "$(cat "$TMPDIR/gutter-after")" ] \
      || fail "campaign-launch drew an execution overlay"
    ALACRITTY_SOCKET="$socket_path" \
      ALACRITTY_WINDOW_ID="$window_id" \
      alacritty msg gutter-event complete

    # Trace IPC remains available to Pi, while both edges stay visually quiet.
    trace() {
      ALACRITTY_SOCKET="$socket_path" ALACRITTY_WINDOW_ID="$window_id" \
        alacritty msg trace-event "$@"
    }
    ALACRITTY_SOCKET="$socket_path" ALACRITTY_WINDOW_ID="$window_id" \
      alacritty msg trace-reset
    xwd -id "$window_id" -silent | magick xwd:- "$TMPDIR/neutral.png"
    TEST_IMAGE="$TMPDIR/neutral.png" python3 - <<'PY'
    import os, subprocess
    image = os.environ['TEST_IMAGE']
    width, height = map(int, subprocess.check_output(['magick', image, '-format', '%w %h', 'info:']).split())
    pixels = subprocess.check_output(['magick', image, '-depth', '8', 'rgb:-'])
    cyan = []
    magenta = []
    for i in range(0, len(pixels), 3):
        color = pixels[i:i+3]
        if color == bytes((0, 255, 255)): cyan.append((i // 3) % width)
        elif color == bytes((255, 0, 255)): magenta.append((i // 3) % width)
    assert cyan and magenta, 'first or last PTY column is missing'
    left, right = min(cyan), width - max(magenta) - 1
    assert abs(left - right) <= 1, ('unequal terminal edge padding', left, right)
    PY
    alacritty msg trace-event --help > "$TMPDIR/trace-help"
    for fact in id parent kind phase status count uncertainty; do
      grep -F -- "--$fact" "$TMPDIR/trace-help" >/dev/null || fail "trace option $fact missing"
    done
    if trace --id 1 --kind arbitrary-ui-text --phase start --status active; then
      fail "untyped kind accepted"
    fi
    if trace --id 1 --kind jev --phase start --status active --uncertainty 1001; then
      fail "out-of-range metric accepted"
    fi
    trace --id 1 --kind codex --phase start --status active
    trace --id 2 --parent 1 --kind fabric --phase start --status active
    trace --id 3 --parent 2 --kind jev --phase start --status active --count 64
    trace --id 3 --parent 2 --kind jev --phase finish --status failed --count 64
    trace --id 2 --parent 1 --kind fabric --phase finish --status failed
    trace --id 1 --kind codex --phase finish --status failed
    sleep 0.15
    xwd -id "$window_id" -silent | magick xwd:- "$TMPDIR/traced.png"
    for image in neutral traced; do
      magick "$TMPDIR/$image.png" -gravity West -crop 150x220+0+0 +repage \
        -format '%#' info: > "$TMPDIR/$image.left"
      magick "$TMPDIR/$image.png" -gravity East -crop 150x220+0+0 +repage \
        -format '%#' info: > "$TMPDIR/$image.right"
    done
    [ "$(cat "$TMPDIR/neutral.left")" = "$(cat "$TMPDIR/traced.left")" ] \
      || fail "Pi trace events drew in the left gutter"
    [ "$(cat "$TMPDIR/neutral.right")" = "$(cat "$TMPDIR/traced.right")" ] \
      || fail "Pi trace events drew in the right padding"
    ALACRITTY_SOCKET="$socket_path" ALACRITTY_WINDOW_ID="$window_id" \
      alacritty msg trace-reset
    mkdir -p "$out/screenshots"
    cp "$TMPDIR/neutral.png" "$TMPDIR/traced.png" "$out/screenshots/"

    # A request without an exact target must fail instead of copying another
    # Alacritty window by accident.
    if env -u ALACRITTY_WINDOW_ID \
      ALACRITTY_SOCKET="$socket_path" \
      alacritty msg copy-buffer --clear \
      > "$TMPDIR/untargeted.stdout" 2> "$TMPDIR/untargeted.stderr"
    then
      fail "an untargeted copy-buffer request unexpectedly succeeded"
    fi
    grep -F 'requires --window-id or ALACRITTY_WINDOW_ID' \
      "$TMPDIR/untargeted.stderr" >/dev/null \
      || fail "an untargeted request failed without the expected diagnostic"

    ALACRITTY_SOCKET="$socket_path" \
      ALACRITTY_WINDOW_ID="$window_id" \
      alacritty msg copy-buffer --clear
    timeout 5 xclip -selection clipboard -out > "$TMPDIR/first-copy"

    grep -Fx 'native-scrollback-marker' "$TMPDIR/first-copy" >/dev/null \
      || fail "copy-buffer omitted content which had scrolled into history"
    grep -Fx 'native-before-tail' "$TMPDIR/first-copy" >/dev/null \
      || fail "copy-buffer omitted the visible tail of the primary buffer"

    # New output after the clear must be captured without any bytes from the
    # previous screen or scrollback.
    touch "$state/release"
    for _ in $(seq 1 100); do
      [ -e "$state/after" ] && break
      sleep 0.05
    done
    [ -e "$state/after" ] || fail "post-clear output fixture timed out"

    ALACRITTY_SOCKET="$socket_path" \
      ALACRITTY_WINDOW_ID="$window_id" \
      alacritty msg copy-buffer --clear
    timeout 5 xclip -selection clipboard -out > "$TMPDIR/second-copy"

    [ "$(cat "$TMPDIR/second-copy")" = 'native-after' ] \
      || fail "the second copy retained pre-clear terminal content"

    touch "$state/exit"
    for _ in $(seq 1 100); do
      kill -0 "$alacritty_pid" 2>/dev/null || break
      sleep 0.05
    done
    if kill -0 "$alacritty_pid" 2>/dev/null; then
      fail "Alacritty did not exit after its fixture command completed"
    fi
    wait "$alacritty_pid"
    alacritty_pid=""

    mkdir -p "$out"
    echo ok > "$out/result"
  ''
