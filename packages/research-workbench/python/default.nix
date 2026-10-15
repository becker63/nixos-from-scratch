{
  lib,
  stdenvNoCC,
  makeWrapper,
  python313,
  callPackage,
}:

let
  jevMcp = callPackage ../../jev-mcp { };
  runtime = python313.withPackages (ps: [
    ps.textual
    ps.textual-plotext
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "attune-textual-workbench";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../events.jsonl
      ../visualizations.jsonl
      ../routing-cases.json
      ../python/client.py
      ../python/events.py
      ../python/visualization.py
      ../python/tests
    ];
  };
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/research-workbench/python $out/bin
    cp $src/python/client.py $src/python/events.py $out/share/research-workbench/python/
    cp $src/python/visualization.py $out/share/research-workbench/python/
    cp $src/events.jsonl $out/share/research-workbench/events.jsonl
    cp $src/visualizations.jsonl $src/routing-cases.json $out/share/research-workbench/
    makeWrapper ${runtime}/bin/python $out/bin/research-textual \
      --add-flags $out/share/research-workbench/python/client.py \
      --set CODEX_JEV_MCP ${jevMcp}/bin/jev-mcp
    runHook postInstall
  '';
  meta = {
    description = "Textual observer for Attune experiments and Codex App Server";
    platforms = lib.platforms.linux;
  };
}
