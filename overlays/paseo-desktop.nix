{
  paseo-src,
  version ? "0.1.59",
}:
final: prev:
let
  lib = prev.lib;
  system = prev.stdenv.hostPlatform.system;
  arch =
    if system == "aarch64-linux" then
      "arm64"
    else if system == "x86_64-linux" then
      "x64"
    else
      throw "paseo-desktop: unsupported system ${system}";

  electron = if prev ? electron_41 then prev.electron_41 else prev.electron;

  runtimeLibs = with prev; [
    libglvnd
    mesa

    glib
    gtk3
    cairo
    pango
    atk
    at-spi2-atk

    nspr
    nss
    dbus
    alsa-lib
    libsecret
    libnotify
    libxkbcommon
    wayland
    cups

    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    libxscrnsaver
    libxtst
    libxi
    libxcursor
    libxrender
  ];

  runtimeLibPath = lib.makeLibraryPath runtimeLibs;
in
{
  paseo-desktop = prev.buildNpmPackage rec {
    pname = "paseo-desktop";
    inherit version;
    src = paseo-src;

    npmDepsHash = "sha256-kw9Lefo644oeeTJCvdFdeW4tbwVMQWqkIVaNonhqbNs=";

    nativeBuildInputs = [
      prev.makeWrapper
      prev.pkg-config
      prev.python3
      prev.git
      prev.wrapGAppsHook4
      prev.makeWrapper
      prev.pkg-config
      prev.python3
      prev.git
      prev.nodejs
      prev.patchelf
      prev.wrapGAppsHook4
    ];

    buildInputs = runtimeLibs ++ [
      prev.gsettings-desktop-schemas
      prev.shared-mime-info
    ];

    dontNpmBuild = true;
    dontNpmPrune = true;
    dontWrapGApps = true;

    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

    postPatch = ''
      mkdir -p packages/desktop/bin

      cat > packages/desktop/bin/paseo <<EOF
      #!${prev.runtimeShell}
      exec ${final.paseo}/bin/paseo "\$@"
      EOF
      chmod +x packages/desktop/bin/paseo
    '';

    buildPhase = ''
      runHook preBuild

      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"

      electron_dist=""
      for p in \
        "${electron}/libexec/electron" \
        "${electron}/lib/electron"
      do
        if [ -d "$p" ]; then
          electron_dist="$p"
          break
        fi
      done

      if [ -z "$electron_dist" ]; then
        echo "Could not locate Electron dist inside ${electron}" >&2
        exit 1
      fi

      npm run build:web --workspace=@getpaseo/app

      # Rebuild native deps (node-pty, etc.) against Electron for this arch.
      (
        cd packages/desktop
        export npm_config_build_from_source=true
        ../../node_modules/.bin/electron-builder install-app-deps
      )

      npm run build --workspace=@getpaseo/desktop -- \
        --publish never \
        --linux dir \
        --${arch} \
        -c.electronVersion=${electron.version} \
        -c.electronDist="$electron_dist"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      appdir="$(find packages/desktop/release -maxdepth 1 -type d -name '*-unpacked' | head -n1)"
      test -n "$appdir"

      mkdir -p "$out/opt"
      cp -r "$appdir" "$out/opt/Paseo"

      mkdir -p "$out/bin"

      mkdir -p "$out/share/applications"
      cat > "$out/share/applications/paseo-desktop.desktop" <<EOF
      [Desktop Entry]
      Name=Paseo
      Exec=$out/bin/paseo-desktop
      Type=Application
      Categories=Development;
      Terminal=false
      EOF

      if [ -f packages/desktop/assets/icon.png ]; then
        install -Dm644 packages/desktop/assets/icon.png \
          "$out/share/pixmaps/paseo-desktop.png"
        printf '\nIcon=paseo-desktop\n' >> "$out/share/applications/paseo-desktop.desktop"
      fi

      runHook postInstall
    '';

    postFixup = ''
      mv "$out/opt/Paseo/Paseo" "$out/opt/Paseo/Paseo-real"
      makeWrapper "$out/opt/Paseo/Paseo-real" "$out/opt/Paseo/Paseo" \
        "''${gappsWrapperArgs[@]}" \
        --prefix LD_LIBRARY_PATH : "${runtimeLibPath}:/run/opengl-driver/lib:/run/opengl-driver-32/lib" \
        --set-default ELECTRON_OZONE_PLATFORM_HINT auto

      ln -s "$out/opt/Paseo/Paseo" "$out/bin/paseo-desktop"
    '';

    meta = with lib; {
      description = "Paseo desktop app";
      homepage = "https://paseo.sh";
      license = licenses.agpl3Plus;
      platforms = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      mainProgram = "paseo-desktop";
    };
  };
}
