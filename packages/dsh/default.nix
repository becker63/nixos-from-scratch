{
  lib,
  buildNpmPackage,
  nodejs_24,
  makeWrapper,
  pnpm,
  ripgrep,
  git,
  bash,
  cacert,
}:
buildNpmPackage {
  pname = "dsh";
  version = "0.2.0-rc.2";
  nodejs = nodejs_24;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
    ];
  };
  npmDepsHash = "sha256-fe4FH3D+Jq8kvDxfK4rQbBubaeesCWm1P5u0MRTAp4I=";
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  dontNpmBuild = true;
  # DSH exposes its runtime services as peers; package.json pins them explicitly
  # so npm's prerelease peer resolution cannot omit services or fetch at build time.
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/dsh" "$out/bin"
    cp -R node_modules package.json "$out/lib/dsh/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/dsh" \
      --add-flags "$out/lib/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js" \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_24
          pnpm
          ripgrep
          git
          bash
        ]
      } \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export DSH_HOME="$TMPDIR/dsh-smoke"
    "$out/bin/dsh" --version
    "$out/bin/dsh" --profile web --dump-config > "$TMPDIR/dsh-config.yml"
    runHook postInstallCheck
  '';
  meta = {
    description = "DeepSeek Harness with the ChatGPT subscription provider";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
