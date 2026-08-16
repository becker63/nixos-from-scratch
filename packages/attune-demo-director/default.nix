{
  alacritty,
  chromium,
  codex,
  ffmpeg,
  git,
  hyprland,
  lib,
  makeWrapper,
  nodejs,
  python3,
  rustPlatform,
  spotify-player,
  swaybg,
  uv,
  wayvnc,
  wf-recorder,
}:

rustPlatform.buildRustPackage {
  pname = "attune-demo-director";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type: type != "directory" || baseNameOf path != "target";
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram "$out/bin/attune-demo-director" \
      --prefix PATH : ${
        lib.makeBinPath [
          alacritty
          chromium
          codex
          ffmpeg
          git
          hyprland
          nodejs
          python3
          spotify-player
          swaybg
          uv
          wayvnc
          wf-recorder
        ]
      }
  '';

  meta = {
    description = "Fail-closed Hyprland capture director for the Attune Campaign A demo";
    license = lib.licenses.mit;
    mainProgram = "attune-demo-director";
    platforms = lib.platforms.linux;
  };
}
