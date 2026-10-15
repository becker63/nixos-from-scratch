{ lib, python3Packages }:

# Same pinned Python/MCP dependencies as Factory; distinct entry point and derivation.
(import ./default.nix { inherit lib python3Packages; }).overrideAttrs (old: {
  pname = "jev-native-mcp";
  postPatch = (old.postPatch or "") + ''
    cp ${../pi-runtime/credential.py} src/jev_mcp/credential.py
    substituteInPlace pyproject.toml --replace-fail 'jev-mcp = "jev_mcp.server:main"' 'jev-mcp = "jev_mcp.server:main"
    jev-native-mcp = "jev_mcp.native:launch"'
  '';
  meta = old.meta // {
    description = "Native TypeSafe Jev MCP with bounded independent-state batching";
    mainProgram = "jev-native-mcp";
  };
})
