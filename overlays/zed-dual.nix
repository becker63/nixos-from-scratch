{
  zed-preview-bin,
}:

final: prev:

let
  inherit (prev) lib stdenvNoCC;

  # Package the official upstream Zed Preview tarball.
  #
  # We avoid `buildFHSEnv` (which leaves runtime resolution to a wrapped
  # /usr/lib view) and instead use `autoPatchelfHook` so every binary gets
  # a proper RUNPATH baked in. Some libraries are loaded via `dlopen()`
  # (Wayland, GL, Vulkan, etc.) and won't appear in DT_NEEDED — those are
  # added through `runtimeDependencies` so the hook still extends RUNPATH
  # to cover them.
  zed-bin = stdenvNoCC.mkDerivation rec {
    pname = "zed-preview-bin";
    version = "preview";

    src = zed-preview-bin;

    nativeBuildInputs = with prev; [
      autoPatchelfHook
      makeWrapper
    ];

    buildInputs = with prev; [
      stdenv.cc.cc.lib
      openssl
      zlib
      glib
      gtk3
      pango
      cairo
      gdk-pixbuf
      fontconfig
      freetype
      libxkbcommon
      wayland
      libGL
      vulkan-loader
      alsa-lib
      util-linux
      libselinux
      libffi
      libx11
      libxcb
      libxau
      libxdmcp
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxrandr
      libxrender
      libxscrnsaver
      libxtst
      nss
      nspr
      dbus
      expat
      cups
    ];

    # Libraries dlopen'd at runtime that aren't in DT_NEEDED. autoPatchelfHook
    # appends these to RUNPATH so dlopen("libGL.so.1") etc. resolves.
    runtimeDependencies = with prev; [
      wayland
      libGL
      vulkan-loader
      libxkbcommon
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/opt/zed.app" "$out/bin" "$out/libexec"

      # The current upstream tarball extracts as bin/, lib/, libexec/, share/
      # at the top level (i.e. it IS the zed.app contents). A future tarball
      # could wrap that in a single zed.app/ directory; handle both.
      if [ -d zed.app ]; then
        cp -R zed.app/. "$out/opt/zed.app/"
      else
        cp -R . "$out/opt/zed.app/"
      fi
      chmod -R u+w "$out/opt/zed.app"

      if [ ! -e "$out/opt/zed.app/bin/zed" ]; then
        echo "error: tarball is missing bin/zed; upstream layout changed?" >&2
        ls -la "$out/opt/zed.app" >&2 || true
        exit 1
      fi

      # Symlink the CLI into $out/bin without wrapping it. The Zed CLI
      # locates the editor binary at ../libexec/zed-editor relative to its
      # own real path, and binaries use RPATH `$ORIGIN/../lib` to find
      # upstream-bundled libs (libffi.so.7, libmount.so.1, etc.) — both
      # rely on the on-disk layout we preserved under $out/opt/zed.app.
      ln -s "$out/opt/zed.app/bin/zed" "$out/bin/zed"
      ln -s "$out/opt/zed.app/bin/zed" "$out/bin/zeditor"

      # Stable diagnostic path for zed-deps-report.
      if [ -e "$out/opt/zed.app/libexec/zed-editor" ]; then
        ln -s "$out/opt/zed.app/libexec/zed-editor" "$out/libexec/zed-editor"
      fi

      # Desktop / icon integration if present.
      if [ -d "$out/opt/zed.app/share" ]; then
        mkdir -p "$out/share"
        for d in "$out/opt/zed.app/share"/*; do
          [ -e "$d" ] || continue
          name=$(basename "$d")
          ln -sfn "$d" "$out/share/$name"
        done
      fi

      runHook postInstall
    '';

    meta = with lib; {
      description = "Zed Preview (upstream binary tarball, autoPatchelf'd)";
      homepage = "https://zed.dev";
      license = licenses.gpl3Plus;
      platforms = [ "aarch64-linux" ];
      mainProgram = "zed";
    };
  };

  zed-deps-report = prev.writeShellApplication {
    name = "zed-deps-report";
    runtimeInputs = with prev; [
      patchelf
      pax-utils
      glibc # ldd
    ];
    text = ''
      set -euo pipefail

      ZED_PKG="${zed-bin}"
      # The auto-patched editor binary that the CLI execs into.
      ZED_EDITOR="$ZED_PKG/opt/zed.app/libexec/zed-editor"

      if [[ ! -e "$ZED_EDITOR" ]]; then
        # Fall back to the stable symlink if upstream layout shifts.
        ZED_EDITOR="$ZED_PKG/libexec/zed-editor"
      fi

      if [[ ! -e "$ZED_EDITOR" ]]; then
        echo "error: editor binary not found under $ZED_PKG" >&2
        echo "hint: build zed first: nix build .#zed_raw" >&2
        exit 1
      fi

      echo "== Zed editor: $ZED_EDITOR"
      echo

      echo "== patchelf --print-needed"
      patchelf --print-needed "$ZED_EDITOR" 2>/dev/null \
        || echo "(patchelf failed — binary may be static or unsupported)" >&2
      echo

      echo "== patchelf --print-rpath"
      patchelf --print-rpath "$ZED_EDITOR" 2>/dev/null \
        || echo "(no RPATH/RUNPATH)" >&2
      echo

      echo "== ldd (direct dynamic deps)"
      ldd "$ZED_EDITOR" 2>/dev/null || echo "(ldd unavailable or not a dynamic ELF)" >&2
      echo

      if command -v lddtree >/dev/null 2>&1; then
        echo "== lddtree"
        lddtree "$ZED_EDITOR"
      else
        echo "== lddtree: not available in PATH"
      fi
      echo

      echo "== missing libraries (from ldd 'not found' lines)"
      if ldd_out="$(ldd "$ZED_EDITOR" 2>/dev/null)"; then
        missing="$(echo "$ldd_out" | grep 'not found' || true)"
        if [[ -n "$missing" ]]; then
          echo "$missing" >&2
          exit 1
        else
          echo "none reported by ldd"
        fi
      else
        echo "(skipped)" >&2
      fi
    '';
  };
in
{
  inherit zed-deps-report;

  zed_raw = zed-bin;

  # Same derivation as zed_raw — autoPatchelfHook handles runtime libs,
  # so no FHS wrapper is needed.
  zed = zed-bin;
}
