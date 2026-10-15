{
  lib,
  stdenvNoCC,
  makeWrapper,
  python313,
}:

let
  runtime = python313.withPackages (ps: [
    ps.textual
    ps.textual-plotext
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "attune-textual-workbench";
  version = "0.1.0";
  src = ../.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/research-workbench/python $out/bin
    cp $src/python/client.py $src/python/events.py $out/share/research-workbench/python/
    cp $src/events.jsonl $out/share/research-workbench/events.jsonl
    makeWrapper ${runtime}/bin/python $out/bin/research-textual \
      --add-flags $out/share/research-workbench/python/client.py
    runHook postInstall
  '';
  meta = {
    description = "Textual observer for Attune experiments and Codex App Server";
    platforms = lib.platforms.linux;
  };
}
