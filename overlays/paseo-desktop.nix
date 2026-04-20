# overlays/paseo-desktop.nix
{ paseo-src, version ? "0.1.59" }:
final: prev:
let
  lib = prev.lib;
  system = prev.stdenv.hostPlatform.system;
  arch =
    if system == "aarch64-linux" then "arm64"
    else if system == "x86_64-linux" then "x64"
    else throw "paseo-desktop: unsupported system ${system}";

  electron =
    if prev ? electron_41 then prev.electron_41 else prev.electron;
in
{
  paseo-desktop = prev.buildNpmPackage rec {
    pname = "paseo-desktop";
    inherit version;
    src = paseo-src;

    # first build: set fakeHash, copy the "got:" hash, rebuild
    npmDepsHash = lib.fakeHash;

    nativeBuildInputs = [
      prev.makeWrapper
      prev.pkg-config
      prev.python3
      prev.git
    ];

    # We build manually.
    dontNpmBuild = true;
    dontNpmPrune = true;

    # Prevent npm/electron install scripts from trying to fetch Electron.
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
      ln -s "$out/opt/Paseo/Paseo" "$out/bin/paseo-desktop"

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

    meta = with lib; {
      description = "Paseo desktop app";
      homepage = "https://paseo.sh";
      license = licenses.agpl3Plus;
      platforms = [ "aarch64-linux" "x86_64-linux" ];
      mainProgram = "paseo-desktop";
    };
  };
}
