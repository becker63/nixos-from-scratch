{
  lib,
  stdenvNoCC,
  makeWrapper,
  python313,
  callPackage,
}:

let
  tunnelClient = callPackage ../../tunnel-client { };
  runtime = python313.withPackages (ps: [ ps.mcp ]);
in
stdenvNoCC.mkDerivation {
  pname = "attune-research-graph-app";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ./server.py
      ./graph.html
      ./tunnel.py
      ../python/visualization.py
      ../visualizations.jsonl
    ];
  };
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/research-workbench/mcp-app/python" "$out/bin"
    cp "$src/mcp-app/server.py" "$src/mcp-app/graph.html" "$src/mcp-app/tunnel.py" "$out/share/research-workbench/mcp-app/"
    cp "$src/python/visualization.py" "$out/share/research-workbench/mcp-app/python/"
    cp "$src/visualizations.jsonl" "$out/share/research-workbench/visualizations.jsonl"
    makeWrapper ${runtime}/bin/python "$out/bin/research-graph-mcp" \
      --add-flags "$out/share/research-workbench/mcp-app/server.py"
    makeWrapper ${runtime}/bin/python "$out/bin/research-graph-tunnel" \
      --add-flags "$out/share/research-workbench/mcp-app/tunnel.py" \
      --add-flags "--tunnel-client ${tunnelClient}/bin/tunnel-client" \
      --add-flags "--mcp-command $out/bin/research-graph-mcp"
    runHook postInstall
  '';
  passthru = { inherit tunnelClient; };
  meta = {
    description = "Inline MCP App chart renderer for Attune research visualizations";
    mainProgram = "research-graph-mcp";
    platforms = lib.platforms.linux;
  };
}
