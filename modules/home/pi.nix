{ pkgs, lib, ... }:
let
  runtime = pkgs.callPackage ../../packages/pi-runtime { };
  root = "${runtime}/lib/pi-runtime";
  settings = {
    defaultProvider = "openai-codex";
    defaultModel = "gpt-6.1-sol";
    defaultThinkingLevel = "medium";
    packages = [
      "${root}/node_modules/pi-fabric"
      "${root}/node_modules/pi-lsp-extension"
    ];
    extensions = [
      "${root}/semantic-extension.ts"
    ];
    tuiMode = "regular";
    skills = [ "${root}/skill" ];
  };
in
{
  home.packages = [ runtime ];
  # Upstream settings remain writable; credentials are never managed.
  home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 - <<'PY'
    import json, os
    from pathlib import Path
    path = Path.home() / '.pi/agent/settings.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    old = json.loads(path.read_text()) if path.exists() else {}
    old.update(json.loads(${builtins.toJSON (builtins.toJSON settings)}))
    temporary = path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(old, indent=2) + '\n')
    os.chmod(temporary, 0o600)
    temporary.replace(path)
    PY
  '';
  home.file.".pi/agent/AGENTS.md".source = ../../packages/pi-runtime/guidance.md;
  home.file.".pi/agent/fabric.json".text = builtins.toJSON {
    configVersion = 4;
    fullCodeMode = true;
    executor = {
      kernel = "typescript";
      runtime = "quickjs";
      timeoutMs = 120000;
      maxTimeoutMs = 300000;
    };
    capture = {
      enabled = true;
      hideFromModel = true;
      keepVisible = [ "fabric_exec" ];
      risks = builtins.listToAttrs (
        map
          (name: {
            inherit name;
            value = "read";
          })
          [
            "lsp_diagnostics"
            "lsp_hover"
            "lsp_definition"
            "lsp_references"
            "lsp_symbols"
            "lsp_rename"
            "lsp_code_actions"
            "lsp_completions"
          ]
      );
    };
    jev = {
      enabled = true;
      model = "jev-1.13.0";
      credentialCommand = [ "${runtime}/bin/pi-jev-credential" ];
      maxEvaluations = 32;
      maxConcurrentRuns = 4;
      maxDurationMs = 300000;
      maxTokens = 20000;
    };
    approvals = {
      read = "allow";
      write = "allow";
      execute = "allow";
      network = "allow";
      agent = "allow";
      actions = { };
    };
    agents = {
      enabled = true;
      runner = "pi";
      model = "openai-codex/gpt-6.1-sol";
      thinking = "medium";
      maxConcurrent = 4;
      maxPerExecution = 4;
      maxDepth = 1;
      timeoutMs = 300000;
      extensions = true;
      defaultTools = [
        "read"
        "bash"
        "edit"
        "write"
        "find"
        "ls"
      ];
      modelAdmission = "strict";
    };
    mcp = {
      enabled = false;
      allowDynamicServers = false;
    };
    memory.enabled = false;
    trace.assessment = true;
  };
}
