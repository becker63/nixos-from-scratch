{
  config,
  pkgs,
  instructions,
  agentsPlugin,
  runtime,
}:

let
  opencodePluginPackages = [
    "@cortexkit/aft-opencode@0.46.0"
    "openrtk@latest"
    "@ramtinj95/opencode-tokenscope@latest"
    "@tarquinen/opencode-dcp@latest"
    "@cortexkit/opencode-magic-context@latest"
    "opencode-model-router@latest"
    "opencode-adaptive-thinking@latest"
    "opencode-pty@latest"
    "@aeondave/opencode-background-agents@latest"
    agentsPlugin.specifier
  ];

  opencodeTuiPluginPackages = opencodePluginPackages;

  opencodeConfig = pkgs.writeText "opencode.json" (
    builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      compaction = {
        auto = false;
        prune = false;
      };
      snapshot = false;
      model = "openai/gpt-5.5-fast";
      small_model = "openai/gpt-5.4-mini-fast";
      instructions = instructions.paths;
      permission = "allow";
      plugin = opencodePluginPackages;
      mcp.postgres-mcp = {
        type = "local";
        command = [
          "${runtime.postgresMcp}/bin/postgres-mcp"
          "--postgres"
          "postgresql://attune@127.0.0.1:54329/postgres"
          "--transport"
          "stdio"
          "--tool-filter"
          "codemode"
          "--audit-log"
          "${config.home.homeDirectory}/.local/state/opencode/postgres-mcp-audit.jsonl"
        ];
        environment = {
          LOG_LEVEL = "warning";
        };
        enabled = true;
        timeout = 30000;
      };
      mcp.zig-docs = {
        type = "local";
        command = [
          "${runtime.opencodeRuntime}/bin/zig-mcp"
          "--doc-source"
          "local"
        ];
        enabled = true;
        timeout = 30000;
      };
      skills.paths = [
        "${config.home.homeDirectory}/.config/opencode/skills"
      ];
    }
  );

  opencodeDcpConfig = pkgs.writeText "opencode-dcp.jsonc" (
    builtins.toJSON {
      "$schema" =
        "https://raw.githubusercontent.com/Opencode-DCP/opencode-dynamic-context-pruning/master/dcp.schema.json";
      enabled = true;
      debug = true;
      pruneNotification = "detailed";
      pruneNotificationType = "chat";
      experimental = {
        allowSubAgents = true;
        customPrompts = false;
      };
      compress = {
        mode = "range";
        permission = "allow";
        showCompression = true;
        summaryBuffer = true;
        minContextLimit = "25%";
        maxContextLimit = "50%";
        nudgeFrequency = 1;
        iterationNudgeThreshold = 8;
        nudgeForce = "strong";
        protectUserMessages = false;
      };
      manualMode = {
        enabled = false;
        automaticStrategies = true;
      };
      strategies = {
        deduplication.enabled = true;
        purgeErrors = {
          enabled = true;
          turns = 4;
        };
      };
    }
  );

  aftConfig = pkgs.writeText "aft.jsonc" (
    builtins.toJSON {
      "$schema" = "https://raw.githubusercontent.com/cortexkit/aft/main/assets/aft.schema.json";
      enabled = true;
      configure_warnings_delivery = "toast";
      tool_surface = "recommended";
      search_index = true;
      semantic_search = true;
      bash = {
        enabled = true;
        rewrite = true;
        compress = true;
        background = true;
      };
      lsp = {
        auto_install = true;
        diagnostics_on_edit = true;
        python = "auto";
      };
    }
  );

  magicContextConfig = pkgs.writeText "magic-context.jsonc" (
    builtins.toJSON {
      enabled = true;
      historian = {
        model = "openai/gpt-5.4-mini-fast";
      };
    }
  );

  opencodeTuiConfig = pkgs.writeText "opencode-tui.jsonc" (
    builtins.toJSON {
      plugin = opencodeTuiPluginPackages;
    }
  );

  opencodeTuiPreferencesConfig = pkgs.writeText "opencode-tui-preferences.jsonc" (
    builtins.toJSON {
      "magic-context" = {
        forceToTop = true;
        order = -100;
        startCollapsed = false;
        rememberCollapsed = true;
        collapsed = false;
        header = {
          label = "Magic Context";
        };
        sections = {
          historian = true;
          memory = true;
          status = true;
          dreamer = true;
          stats = true;
        };
      };
      aft = {
        collapsed = false;
      };
    }
  );

in
{
  inherit
    opencodeConfig
    opencodeDcpConfig
    aftConfig
    magicContextConfig
    opencodeTuiConfig
    opencodeTuiPreferencesConfig
    ;

  xdgConfigFiles = {
    "cortexkit/aft.jsonc".source = aftConfig;
    "cortexkit/magic-context.jsonc".source = magicContextConfig;
    "opencode/dcp.jsonc".source = opencodeDcpConfig;
    "opencode/opencode.json".source = opencodeConfig;
    "opencode/tui.jsonc".source = opencodeTuiConfig;
    "opencode/tui-preferences.jsonc".source = opencodeTuiPreferencesConfig;
  };
}
