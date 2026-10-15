{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libusb1,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  openssl,
  pango,
  qt5,
  qt6,
  stdenv,
  systemd,
  tpm2-tss,
  vulkan-loader,
  wayland,
  xdg-utils,
}:

stdenvNoCC.mkDerivation rec {
  pname = "chatgpt-desktop";
  version = "26.930.21537";

  # Official ARM64 package, pinned to a versioned artifact rather than latest.
  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_arm64.deb";
    hash = "sha256-9kbAHuvTekkxfvYq7eh3wina7uTxyrnvPrYaHPZClWQ=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libgbm
    libnotify
    libusb1
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    openssl
    pango
    # Chromium ships separate Qt 5/6 shims; only their runtime libraries
    # belong here, since the two development setup hooks cannot coexist.
    (lib.getLib qt5.qtbase)
    (lib.getLib qt6.qtbase)
    stdenv.cc.cc.lib
    systemd
    tpm2-tss
  ];

  # Chromium loads graphics backends dynamically rather than via DT_NEEDED.
  runtimeDependencies = [
    libGL
    libgbm
    vulkan-loader
    wayland
  ];

  unpackPhase = ''
    runHook preUnpack
    ar p "$src" data.tar.xz | tar -xJ
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontWrapQtApps = true;
  # Preserve the vendor binaries and native Node modules without stripping.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/bin"
    cp -a usr/lib/chatgpt "$out/lib/"
    cp -a usr/share "$out/"
    chmod -R u+w "$out"

    # Android's ARM64 Node prebuilds use Bionic, not the Linux glibc ABI.
    find "$out/lib/chatgpt/resources" -type d \
      -path '*/prebuilds/android-*' -prune -exec rm -rf {} +

    makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib \
      --prefix XDG_DATA_DIRS : "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:${gtk3}/share/gsettings-schemas/${gtk3.name}" \
      --suffix PATH : ${
        lib.makeBinPath [
          xdg-utils
          glib
          libnotify
        ]
      }
    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail 'Exec=chatgpt %U' "Exec=$out/bin/chatgpt %U"
    runHook postInstall
  '';

  meta = {
    description = "Official ChatGPT desktop app for Linux";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = [ "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
