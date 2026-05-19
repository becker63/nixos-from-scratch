{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cursorHermesWorkspace = "/home/becker/nixos-from-scratch";
  cursorHermesStateDir = "/home/becker/.local/share/hermes";
  cursorHermesModel = "auto";

  cursorHermesBridge = pkgs.writeShellScriptBin "cursor-hermes-bridge" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/cursor_hermes_bridge.py}
  '';
in
{
  imports = [ inputs.nix-hermes.nixosModules.hermes-agent ];

  systemd.services.cursor-hermes-bridge = {
    description = "Cursor to Hermes OpenAI-compatible bridge";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      HOME = "/home/becker";
      CURSOR_HERMES_BRIDGE_HOST = "127.0.0.1";
      CURSOR_HERMES_BRIDGE_PORT = "8383";
      CURSOR_HERMES_WORKSPACE = cursorHermesWorkspace;
      CURSOR_HERMES_MODEL = cursorHermesModel;
    };

    serviceConfig = {
      User = "becker";
      Group = "users";
      WorkingDirectory = cursorHermesWorkspace;
      ExecStart = "${cursorHermesBridge}/bin/cursor-hermes-bridge";
      Restart = "always";
      RestartSec = 2;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = false;
      ReadWritePaths = [
        "/home/becker/.config/cursor"
        "/home/becker/.cursor"
        "/home/becker/.local/share/cursor-agent"
        cursorHermesWorkspace
      ];
      PrivateTmp = true;
    };

    path = with pkgs; [
      bash
      coreutils
      git
      python3
    ];
  };

  services.hermes-agent = {
    enable = true;
    user = "becker";
    group = "users";
    createUser = false;
    stateDir = cursorHermesStateDir;
    workingDirectory = cursorHermesWorkspace;
    skills.bundled.enable = false;

    config = {
      model = {
        default = cursorHermesModel;
        provider = "custom";
        base_url = "http://127.0.0.1:8383/v1";
      };

      terminal = {
        backend = "local";
        cwd = cursorHermesWorkspace;
        timeout = 180;
        lifetime_seconds = 300;
      };

      agent = {
        max_turns = 60;
      };

      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
        memory_char_limit = 2200;
      };

      compression = {
        enabled = true;
        threshold = 0.85;
        summary_model = "google/gemini-3-flash-preview";
      };

      platform_toolsets = {
        local = [ "all" ];
      };
    };

    documents = {
      "SOUL.md" = ''
        # SOUL.md

        You are Hermes running on Taylor's machine through a local Cursor-backed bridge.
        Default to careful, pragmatic engineering help and explain tradeoffs plainly.
      '';
      "AGENTS.md" = ''
        # AGENTS.md

        You are operating on a personal NixOS workstation.
        Prefer inspecting the local repository state before proposing changes.
        Be explicit when a task depends on external services or account credentials.
      '';
      "USER.md" = ''
        # USER.md

        Name: Taylor Johnson
        Preferred stack: NixOS, Linux, networking, developer tooling, AI evaluation systems.
      '';
    };

    extraPackages = with pkgs; [
      curl
      git
      jq
      ripgrep
    ];
  };

  systemd.services.hermes-agent = {
    after = [ "cursor-hermes-bridge.service" ];
    wants = [ "cursor-hermes-bridge.service" ];
  };
}
