{
  lib,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "factory-config-merge";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ python3 ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m unittest -v test_factory_config.py
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -D -m 755 factory-config-merge.py \
      "$out/bin/factory-config-merge"
    patchShebangs "$out/bin/factory-config-merge"
    runHook postInstall
  '';

  meta = {
    description = "Safely merge Nix-owned defaults into mutable Factory user configuration";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "factory-config-merge";
  };
}
