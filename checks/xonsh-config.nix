{ pkgs, sourceRoot }:

let
  alacrittyMock = pkgs.writeShellScriptBin "alacritty" ''
    printf '%s\n' "$*" >> "$ALACRITTY_MOCK_LOG"
    exit "''${ALACRITTY_MOCK_STATUS:-0}"
  '';
  yekMock = pkgs.writeShellScriptBin "yek" ''
    printf '%s %s\n' "$RAYON_NUM_THREADS" "$*" >> "$YEK_MOCK_LOG"
    mkdir -p /tmp/yek-output
    printf 'mock packed repository\n' > /tmp/yek-output/chatgpt-context.txt
    exit "''${YEK_MOCK_STATUS:-0}"
  '';
  wlCopyMock = pkgs.writeShellScriptBin "wl-copy" ''
    cat > "$WL_COPY_MOCK_OUTPUT"
  '';
  wlPasteMock = pkgs.writeShellScriptBin "wl-paste" ''
    cat "$CB_CAPTURE"
  '';
  codexMock = pkgs.writeShellScriptBin "codex" ''
    printf '%s\n' "$*" >> "$CODEX_MOCK_LOG"
  '';
in
pkgs.runCommand "xonsh-config-check"
  {
    nativeBuildInputs = [
      alacrittyMock
      yekMock
      wlCopyMock
      wlPasteMock
      codexMock
      pkgs.atuin
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.ncurses
      pkgs.python313Packages.pyclip
      pkgs.python313Packages.jedi
      pkgs.starship
      pkgs.xonsh
    ];
  }
  ''
    set -euo pipefail

    fail() {
      echo "FAIL: $*" >&2
      exit 1
    }

    rc='${sourceRoot}/config/xonsh/rc.xsh'
    export HOME="$TMPDIR/home"
    export XONSH_DATA_DIR="$TMPDIR/xonsh-data"
    mkdir -p "$HOME" "$XONSH_DATA_DIR"
    # Prompt xontribs are packaged by an overlay and are not relevant to these
    # shell semantics, so test a copy of the RC without their two load lines.
    test_rc="$TMPDIR/rc.xsh"
    sed '/^xontrib load /d' "$rc" > "$test_rc"

    # Failed interactive commands must leave the xonsh process alive.
    ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c 'false; print("shell-survived")' \
      > "$TMPDIR/failed-command-output" || true
    grep -Fx 'shell-survived' "$TMPDIR/failed-command-output" >/dev/null \
      || fail "a failed command terminates xonsh"

    ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'assert aliases["cst"] == ["uv", "run", "python", "-m", "libcst.tool"]; assert aliases["griffe"] == ["uv", "run", "python", "-m", "griffe"]; print("refactor-tools-wired")' \
      | grep -Fx 'refactor-tools-wired' >/dev/null \
      || fail "Xonsh refactoring tool aliases are not wired"

    # Model a small uv project without consulting anything under /home. The
    # shell must expose both src-layout project code and installed packages.
    workspace="$TMPDIR/uv-workspace"
    mkdir -p "$workspace/src/check_workspace" \
      "$workspace/.venv/lib/python3.13/site-packages"
    touch "$workspace/pyproject.toml"
    printf '__version__ = "project"\n' > "$workspace/src/check_workspace/__init__.py"
    printf 'value = "search"\ndef search():\n    return value\n' > "$workspace/src/check_workspace/search.py"
    printf '__version__ = "venv"\n' > "$workspace/.venv/lib/python3.13/site-packages/check_dependency.py"

    TEST_UV_PROJECT="$workspace" ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'import os; refresh_uv_workspace_imports(os.environ["TEST_UV_PROJECT"]); import check_dependency; import check_workspace; from xonsh.completer import Completer; modules, _ = Completer().complete_line("check_workspace."); symbols, _ = Completer().complete_line("check_workspace.search."); assert "search" in modules; assert "search" in symbols; assert check_dependency.__version__ == "venv"; assert check_workspace.__version__ == "project"; print("uv-workspace-imports-work")' \
      | grep -Fx 'uv-workspace-imports-work' >/dev/null \
      || fail "uv workspace imports are unavailable"

    # All public copybuffer names clear Alacritty while retaining a cumulative
    # private transcript for the next capture.
    export ALACRITTY_MOCK_LOG="$TMPDIR/alacritty-calls"
    export ALACRITTY_WINDOW_ID=copybuffer-fixture
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    export CB_CAPTURE="$TMPDIR/copybuffer-capture"
    export WL_COPY_MOCK_OUTPUT="$TMPDIR/copybuffer-clipboard"
    mkdir -p "$XDG_RUNTIME_DIR"
    printf 'mock terminal capture\n' > "$CB_CAPTURE"
    ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'assert callable(aliases["cb"]); assert callable(aliases["copybuffer"]); assert callable(aliases["copyall"]); print("copybuffer-aliases-callable")' \
      | grep -Fx 'copybuffer-aliases-callable' >/dev/null \
      || fail "copybuffer aliases are not callable"
    for command in cb copybuffer copyall; do
      ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c "$command" \
        || fail "$command failed through Xonsh command dispatch"
    done
    ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'assert aliases["cb"]([], None) == 0; print("copybuffer-command-wired")' \
      | grep -Fx 'copybuffer-command-wired' >/dev/null \
      || fail "copybuffer command is not wired"
    test "$(wc -l < "$ALACRITTY_MOCK_LOG")" -eq 4 \
      || fail "copybuffer aliases did not dispatch exactly once per invocation"
    test "$(sort -u "$ALACRITTY_MOCK_LOG")" = 'msg copy-buffer --clear' \
      || fail "copybuffer aliases did not clear Alacritty"
    test "$(grep -cFx 'mock terminal capture' "$WL_COPY_MOCK_OUTPUT")" -eq 4 \
      || fail "copybuffer did not retain all previous captures"

    # `rp` is the deliberately high-throughput repository packer: it uses
    # Yek's parallel Rust implementation with every available CPU, avoids
    # token accounting and repository-specific Yek configuration, then copies
    # the generated context to the Wayland clipboard.
    export YEK_MOCK_LOG="$TMPDIR/yek-calls"
    export WL_COPY_MOCK_OUTPUT="$TMPDIR/yek-clipboard"
    ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'assert callable(aliases["rp"]); assert aliases["rp"](["."], None) == 0; print("rapidpack-wired")' \
      | grep -Fx 'rapidpack-wired' >/dev/null \
      || fail "rapidpack alias is not wired"
    test "$(wc -l < "$YEK_MOCK_LOG")" -eq 1 \
      || fail "rapidpack did not invoke Yek exactly once"
    awk 'NF == 5 && $1 >= 1 && $2 == "--no-config" && $3 == "--output-name" && $4 == "chatgpt-context.txt" && $5 == "." { found = 1 } END { exit !found }' "$YEK_MOCK_LOG" \
      || fail "rapidpack did not enable its parallel no-overhead Yek mode"
    test "$(cat "$WL_COPY_MOCK_OUTPUT")" = 'mock packed repository' \
      || fail "rapidpack did not copy Yek output to the clipboard"

    ALACRITTY_MOCK_STATUS=23 ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'assert aliases["cb"]([], None) == 23; print("copybuffer-status-propagated")' \
      | grep -Fx 'copybuffer-status-propagated' >/dev/null \
      || fail "copybuffer does not propagate Alacritty IPC failures"

    ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'assert aliases["cb"](["unexpected"], None) == 2; print("copybuffer-args-rejected")' \
      | grep -Fx 'copybuffer-args-rejected' >/dev/null \
      || fail "copybuffer accepts unexpected arguments"

    # Codex brackets only its own terminal interval with typed, per-window IPC
    # events. Missing Alacritty targeting metadata remains a silent no-op.
    export CODEX_MOCK_LOG="$TMPDIR/codex-calls"
    : > "$ALACRITTY_MOCK_LOG"
    unset ALACRITTY_SOCKET
    ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'assert _gutter_event("codex-start") is False' \
      || fail "gutter IPC did not tolerate missing targeting metadata"
    test ! -s "$ALACRITTY_MOCK_LOG" \
      || fail "gutter IPC escaped its Alacritty targeting gate"
    export ALACRITTY_SOCKET="$TMPDIR/alacritty.sock"
    ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'assert callable(aliases["codex"]); codex resume' \
      || fail "codex alias did not run"
    test "$(cat "$CODEX_MOCK_LOG")" = 'resume' \
      || fail "codex alias did not invoke Codex"
    test "$(cat "$ALACRITTY_MOCK_LOG")" = $'msg gutter-event codex-start\nmsg gutter-event codex-stop' \
      || fail "codex did not bracket its run with typed gutter events"

    # Interactive command lifecycle events synthesize gutter scopes. Calling
    # the event bus directly keeps this check deterministic under `xonsh -c`,
    # where Xonsh intentionally does not fire interactive lifecycle hooks.
    : > "$ALACRITTY_MOCK_LOG"
    ${pkgs.xonsh}/bin/xonsh --rc "$test_rc" -c \
      'events.on_precommand.fire(cmd="pytest"); events.on_postcommand.fire(cmd="pytest", rtn=0, out=None, ts=[0, 1]); events.on_precommand.fire(cmd="false"); events.on_postcommand.fire(cmd="false", rtn=1, out=None, ts=[1, 2])' \
      || fail "command lifecycle gutter hooks failed"
    test "$(cat "$ALACRITTY_MOCK_LOG")" = $'msg gutter-event command-start\nmsg gutter-event command-pass\nmsg gutter-event command-start\nmsg gutter-event command-fail' \
      || fail "command lifecycle hooks emitted the wrong gutter events"

    ! grep -Eiq 'wtype|asciinema' "$rc" \
      || fail "removed copybuffer backends remain in Xonsh"

    mkdir -p "$out"
    echo ok > "$out/result"
  ''
