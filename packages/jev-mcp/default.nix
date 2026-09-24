{
  lib,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "jev-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = with python3Packages; [ setuptools ];
  dependencies = with python3Packages; [
    httpx
    mcp
  ];

  nativeCheckInputs = with python3Packages; [
    pytest-asyncio
    pytestCheckHook
  ];

  pythonImportsCheck = [ "jev_mcp" ];

  meta = {
    description = "MCP server for bounded semantic decisions with Jev";
    license = lib.licenses.mit;
    mainProgram = "jev-mcp";
    platforms = lib.platforms.unix;
  };
}
