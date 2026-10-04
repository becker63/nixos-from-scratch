{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  autoPatchelfHook,
  makeWrapper,
  cacert,
  git,
  ripgrep,
  stdenv,
}:
let
  system = stdenvNoCC.hostPlatform.system;
  archive =
    {
      aarch64-linux = {
        arch = "aarch64";
        hash = "sha256-on/7Y6gxA3WDbg1vZorhf6jY0YuIw3yCHGUzGXOhmjs=";
      };
      x86_64-linux = {
        arch = "x64";
        hash = "sha256-lR7iruhV8IWVruxiJSJqKY0/6oOj3NZGXAnLzN9+hI8=";
      };
    }
    .${system};
  bun = stdenvNoCC.mkDerivation {
    pname = "bun-morph-lab";
    version = "1.3.14";
    src = fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.14/bun-linux-${archive.arch}.zip";
      inherit (archive) hash;
    };
    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];
    buildInputs = [ stdenv.cc.cc.lib ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 bun "$out/bin/bun"
      runHook postInstall
    '';
  };
  # Only explicit source files enter the store. Runtime .env is never a Nix input.
  source = lib.fileset.toSource {
    root = ./source;
    fileset = lib.fileset.unions [
      ./source/package.json
      ./source/bun.lock
      ./source/src
      ./source/scripts/plugin-host.ts
      ./source/upstream/oh-my-pi-plugin-morph/src
      ./source/upstream/oh-my-pi-plugin-morph/LICENSE
      ./source/upstream/oh-my-pi-plugin-morph/package.json
    ];
  };
  nodeModules = stdenvNoCC.mkDerivation {
    pname = "morph-lab-node-modules";
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ bun ];
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-kKqNpcYNCKDPLGcORYx7/+DNZ4Hgi0uZQpEiJgcQZDk=";
    buildPhase = ''
      mkdir work
      cd work
      cp ${source}/package.json ${source}/bun.lock .
      export BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
      bun install --frozen-lockfile --production --ignore-scripts --backend=copyfile --cpu='*' --os=linux
    '';
    installPhase = ''
      cp -R node_modules "$out"
    '';
    # Architecture-independent cache includes every Linux CPU's optional package.
    dontFixup = true;
  };
in
stdenvNoCC.mkDerivation {
  pname = "morph-lab";
  version = "0.1.0";
  src = source;
  nativeBuildInputs = [ makeWrapper ];
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/morph-lab" "$out/bin"
    cp -R src scripts upstream package.json bun.lock "$out/lib/morph-lab/"
    # Preserve the real node_modules path: Pi detects native leaf packages from it.
    cp -R ${nodeModules} "$out/lib/morph-lab/node_modules"
    makeWrapper ${bun}/bin/bun "$out/bin/morph-lab" \
      --add-flags "--no-env-file $out/lib/morph-lab/src/cli.ts" \
      --prefix PATH : ${
        lib.makeBinPath [
          bun
          git
          ripgrep
        ]
      } \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --set-default MORPH_LAB_DECISION_PROVIDER jev \
      --run 'export MORPH_LAB_ENV_FILE="''${MORPH_LAB_ENV_FILE:-$HOME/nixos-from-scratch/.env}"' \
      --run 'export MORPH_LAB_DEFAULT_REPO="''${MORPH_LAB_DEFAULT_REPO:-$HOME/projects/attuneflix-tree-reuse}"'
    runHook postInstall
  '';
  dontFixup = true;
  meta = {
    description = "Small Jev decision workflow with Morph specialists and Pi fallback";
    mainProgram = "morph-lab";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
