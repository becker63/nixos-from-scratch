{ mini-swe-agent-src }:

final: _prev:

let
  python = final.python313Packages;
in
{
  mini-swe-agent = python.buildPythonApplication {
    pname = "mini-swe-agent";
    version = "2.4.6";
    src = mini-swe-agent-src;
    pyproject = true;

    build-system = [ python.setuptools ];
    dependencies = with python; [
      datasets
      jinja2
      litellm
      openai
      platformdirs
      prompt-toolkit
      pydantic
      python-dotenv
      pyyaml
      requests
      rich
      tenacity
      textual
      typer
    ];

    patches = [ ../patches/mini-swe-agent-xonsh.patch ];

    postPatch = ''
      substituteInPlace src/minisweagent/models/utils/actions_toolcall.py \
        --replace-fail 'if tool_call.function.name != "bash":' 'if tool_call.function.name != "xonsh":' \
        --replace-fail "Missing 'command' argument in bash tool call." "Missing 'command' argument in xonsh tool call."
      substituteInPlace src/minisweagent/models/utils/actions_toolcall_response.py \
        --replace-fail 'if tool_call.get("name") != "bash":' 'if tool_call.get("name") != "xonsh":' \
        --replace-fail "Missing 'command' argument in bash tool call." "Missing 'command' argument in xonsh tool call."
    '';

    doCheck = false;
  };
}
