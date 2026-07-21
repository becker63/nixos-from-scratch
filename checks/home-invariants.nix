{
  pkgs,
  systemConfig,
}:

let
  inherit (pkgs) lib;

  homeConfig = systemConfig.home-manager.users.becker;
  homeFiles = homeConfig."home-files";
  activationPackage = homeConfig.home.activationPackage;

  getHome = path: fallback: lib.attrByPath path fallback homeConfig;
  getSystem = path: fallback: lib.attrByPath path fallback systemConfig;

  packageNames = map lib.getName homeConfig.home.packages;
  packagesNamed =
    name: builtins.filter (package: lib.getName package == name) homeConfig.home.packages;

  configFileNames = builtins.attrNames homeConfig.xdg.configFile;
  hasConfigFile = name: builtins.hasAttr name homeConfig.xdg.configFile;
  configFilesUnder =
    root:
    builtins.filter (
      name:
      let
        normalized = lib.toLower name;
      in
      normalized == root || lib.hasPrefix "${root}/" normalized
    ) configFileNames;

  retainedDesktopConfigFiles = [
    "alacritty"
    "atuin"
    "eww"
    "fastfetch"
    "hypr"
    "starship"
    "sway"
    "tofi"
    "xonsh"
    "zed"
  ];

  opencodeConfigFiles = [
    "cortexkit/aft.jsonc"
    "cortexkit/magic-context.jsonc"
    "opencode/dcp.jsonc"
    "opencode/opencode.json"
    "opencode/tui.jsonc"
    "opencode/tui-preferences.jsonc"
  ];

  forbiddenConfigRoots = [
    "arttime"
    "kitty"
    "neovim"
    "nvim"
    "pi"
    "tmux"
    "tmuxp"
    "waybar"
    "wofi"
  ];

  forbiddenPackageGroups = {
    arttime = [ "arttime" ];
    kitty = [ "kitty" ];
    neovim = [
      "neovim"
      "neovim-unwrapped"
      "nvim"
    ];
    pi = [
      "pi"
      "pi-agent"
      "pi-coding-agent"
    ];
    tmux = [
      "tmux"
      "tmuxp"
    ];
    waybar = [ "waybar" ];
    wofi = [ "wofi" ];
  };

  forbiddenPackagesPresent = names: builtins.filter (name: builtins.elem name names) packageNames;

  opencodeRuntimePackages = packagesNamed "opencode-runtime";
  opencodeWrapperPackages = packagesNamed "opencode-with-tooling";
  opencodeRuntime =
    if opencodeRuntimePackages == [ ] then null else builtins.head opencodeRuntimePackages;
  opencodeWrapper =
    if opencodeWrapperPackages == [ ] then null else builtins.head opencodeWrapperPackages;
  opencodeRuntimePath =
    if opencodeRuntime == null then "/missing/opencode-runtime" else toString opencodeRuntime;
  opencodeWrapperPath =
    if opencodeWrapper == null then "/missing/opencode-with-tooling" else toString opencodeWrapper;

  ewwService = getHome [ "systemd" "user" "services" "eww-osd" ] { };
  ewwUnit = lib.attrByPath [ "Unit" ] { } ewwService;
  ewwServiceConfig = lib.attrByPath [ "Service" ] { } ewwService;
  ewwInstall = lib.attrByPath [ "Install" ] { } ewwService;
  ewwHotspotScript = lib.attrByPath [
    "ExecStartPost"
  ] "/missing/eww-power-hotspot-start" ewwServiceConfig;

  homeManagerService = getSystem [ "systemd" "services" "home-manager-becker" ] { };

  bashInit = getHome [ "programs" "bash" "initExtra" ] "";

  checks = [
    {
      name = "Home Manager username";
      pass = getHome [ "home" "username" ] null == "becker";
      expected = "becker";
      actual = getHome [ "home" "username" ] null;
    }
    {
      name = "Home Manager home directory";
      pass = getHome [ "home" "homeDirectory" ] null == "/home/becker";
      expected = "/home/becker";
      actual = getHome [ "home" "homeDirectory" ] null;
    }
    {
      name = "Home Manager state version";
      pass = getHome [ "home" "stateVersion" ] null == "25.05";
      expected = "25.05";
      actual = getHome [ "home" "stateVersion" ] null;
    }
    {
      name = "Home Manager release check policy";
      pass = getHome [ "home" "enableNixpkgsReleaseCheck" ] true == false;
      expected = false;
      actual = getHome [ "home" "enableNixpkgsReleaseCheck" ] null;
    }
    {
      name = "NixOS user home directory";
      pass = getSystem [ "users" "users" "becker" "home" ] null == "/home/becker";
      expected = "/home/becker";
      actual = getSystem [ "users" "users" "becker" "home" ] null;
    }
    {
      name = "NixOS user remains a normal user";
      pass = getSystem [ "users" "users" "becker" "isNormalUser" ] false;
      expected = true;
      actual = getSystem [ "users" "users" "becker" "isNormalUser" ] null;
    }
    {
      name = "Xonsh remains the login shell";
      pass = toString (getSystem [ "users" "users" "becker" "shell" ] "") == "${pkgs.xonsh}/bin/xonsh";
      expected = "xonsh";
      actual = toString (getSystem [ "users" "users" "becker" "shell" ] "");
    }
    {
      name = "Xonsh remains an allowed shell";
      pass = builtins.elem "${pkgs.xonsh}/bin/xonsh" (
        map toString (getSystem [ "environment" "shells" ] [ ])
      );
      expected = true;
      actual = builtins.elem "${pkgs.xonsh}/bin/xonsh" (
        map toString (getSystem [ "environment" "shells" ] [ ])
      );
    }
    {
      name = "Home Manager backup extension";
      pass = getSystem [ "home-manager" "backupFileExtension" ] null == "backup";
      expected = "backup";
      actual = getSystem [ "home-manager" "backupFileExtension" ] null;
    }
    {
      name = "Home Manager activation service user";
      pass = lib.attrByPath [ "serviceConfig" "User" ] null homeManagerService == "becker";
      expected = "becker";
      actual = lib.attrByPath [ "serviceConfig" "User" ] null homeManagerService;
    }
    {
      name = "Home Manager activation remains boot-integrated";
      pass = builtins.elem "multi-user.target" (lib.attrByPath [ "wantedBy" ] [ ] homeManagerService);
      expected = true;
      actual = lib.attrByPath [ "wantedBy" ] [ ] homeManagerService;
    }
    {
      name = "Atuin enabled";
      pass = getHome [ "programs" "atuin" "enable" ] false;
      expected = true;
      actual = getHome [ "programs" "atuin" "enable" ] null;
    }
    {
      name = "Atuin daemon remains disabled";
      pass = getHome [ "programs" "atuin" "daemon" "enable" ] true == false;
      expected = false;
      actual = getHome [ "programs" "atuin" "daemon" "enable" ] null;
    }
    {
      name = "Atuin Bash integration enabled";
      pass = getHome [ "programs" "atuin" "enableBashIntegration" ] false;
      expected = true;
      actual = getHome [ "programs" "atuin" "enableBashIntegration" ] null;
    }
    {
      name = "Bash enabled";
      pass = getHome [ "programs" "bash" "enable" ] false;
      expected = true;
      actual = getHome [ "programs" "bash" "enable" ] null;
    }
    {
      name = "Bash workspace prompt retained";
      pass =
        lib.hasInfix "get_workspace()" bashInit
        && lib.hasInfix "hyprctl monitors -j" bashInit
        && lib.hasInfix "[WS:" bashInit;
      expected = "workspace-aware PS1";
      actual = if lib.hasInfix "get_workspace()" bashInit then "present" else "missing";
    }
    {
      name = "Generated Bash initialization includes Atuin";
      pass = lib.hasInfix "atuin init bash" bashInit;
      expected = "atuin init bash";
      actual = if lib.hasInfix "atuin init bash" bashInit then "present" else "missing";
    }
    {
      name = "Git enabled";
      pass = getHome [ "programs" "git" "enable" ] false;
      expected = true;
      actual = getHome [ "programs" "git" "enable" ] null;
    }
    {
      name = "Git identity";
      pass =
        getHome [ "programs" "git" "settings" "user" "name" ] null == "becker63"
        && getHome [ "programs" "git" "settings" "user" "email" ] null == "johnsontaylor6320@gmail.com";
      expected = "becker63 <johnsontaylor6320@gmail.com>";
      actual = "${toString (getHome [ "programs" "git" "settings" "user" "name" ] "<missing>")} <${
        toString (getHome [ "programs" "git" "settings" "user" "email" ] "<missing>")
      }>";
    }
    {
      name = "Git workflow settings";
      pass =
        getHome [ "programs" "git" "settings" "init" "defaultBranch" ] null == "main"
        && getHome [ "programs" "git" "settings" "pull" "rebase" ] false
        && getHome [ "programs" "git" "settings" "credential" "helper" ] null == "!gh auth git-credential";
      expected = "main branch, pull.rebase, gh credential helper";
      actual = "evaluated Git settings";
    }
    {
      name = "Eww OSD daemon command";
      pass =
        lib.attrByPath [ "ExecStart" ] [ ] ewwServiceConfig
        == [ "${pkgs.eww}/bin/eww daemon --no-daemonize" ];
      expected = "eww daemon --no-daemonize";
      actual = lib.attrByPath [ "ExecStart" ] [ ] ewwServiceConfig;
    }
    {
      name = "Eww OSD reload command";
      pass = lib.attrByPath [ "ExecReload" ] null ewwServiceConfig == "${pkgs.eww}/bin/eww reload";
      expected = "eww reload";
      actual = lib.attrByPath [ "ExecReload" ] null ewwServiceConfig;
    }
    {
      name = "Eww OSD lifecycle";
      pass =
        lib.attrByPath [ "After" ] [ ] ewwUnit == [ "graphical-session.target" ]
        && lib.attrByPath [ "PartOf" ] [ ] ewwUnit == [ "graphical-session.target" ]
        && lib.attrByPath [ "WantedBy" ] [ ] ewwInstall == [ "graphical-session.target" ]
        && lib.attrByPath [ "Restart" ] null ewwServiceConfig == "on-failure"
        && lib.attrByPath [ "RestartSec" ] null ewwServiceConfig == 1;
      expected = "graphical-session lifecycle with on-failure restart";
      actual = "evaluated Eww unit";
    }
    {
      name = "npm global session path";
      pass = getHome [ "home" "sessionPath" ] [ ] == [ "/home/becker/.npm-global/bin" ];
      expected = [ "/home/becker/.npm-global/bin" ];
      actual = getHome [ "home" "sessionPath" ] [ ];
    }
    {
      name = "npm prefix configuration";
      pass = getHome [ "home" "file" ".npmrc" "text" ] null == "prefix=/home/becker/.npm-global\n";
      expected = "prefix=/home/becker/.npm-global";
      actual = getHome [ "home" "file" ".npmrc" "text" ] null;
    }
    {
      name = "OpenCode runtime package appears exactly once";
      pass = builtins.length opencodeRuntimePackages == 1;
      expected = 1;
      actual = builtins.length opencodeRuntimePackages;
    }
    {
      name = "OpenCode tooling wrapper appears exactly once";
      pass = builtins.length opencodeWrapperPackages == 1;
      expected = 1;
      actual = builtins.length opencodeWrapperPackages;
    }
  ]
  ++ map (name: {
    name = "retained XDG config link: ${name}";
    pass = hasConfigFile name;
    expected = true;
    actual = hasConfigFile name;
  }) retainedDesktopConfigFiles
  ++ map (name: {
    name = "OpenCode XDG config: ${name}";
    pass = hasConfigFile name;
    expected = true;
    actual = hasConfigFile name;
  }) opencodeConfigFiles
  ++ map (root: {
    name = "removed XDG config root stays absent: ${root}";
    pass = configFilesUnder root == [ ];
    expected = [ ];
    actual = configFilesUnder root;
  }) forbiddenConfigRoots
  ++ lib.mapAttrsToList (group: names: {
    name = "removed Home package stays absent: ${group}";
    pass = forbiddenPackagesPresent names == [ ];
    expected = [ ];
    actual = forbiddenPackagesPresent names;
  }) forbiddenPackageGroups;

  manifest = pkgs.writeText "home-invariants.json" (
    builtins.toJSON {
      inherit checks configFileNames packageNames;
    }
  );

  preflight = pkgs.writeShellApplication {
    name = "home-invariants";
    runtimeInputs = with pkgs; [
      coreutils
      git
      gnugrep
      jq
    ];
    text = ''
      set -euo pipefail

      fail() {
        echo "FAIL: $*" >&2
        exit 1
      }

      if jq -e 'any(.checks[]; .pass != true)' '${manifest}' >/dev/null; then
        echo "Home Manager invariants failed:" >&2
        jq -r '.checks[] | select(.pass != true) | "  - \(.name): expected \(.expected | tojson), got \(.actual | tojson)"' '${manifest}' >&2
        exit 1
      fi

      home_files='${homeFiles}'
      activation_package='${activationPackage}'
      [ -d "$home_files" ] || fail "Home Manager home-files output is missing"
      [ -x "$activation_package/activate" ] || fail "Home Manager activation script is missing"
      [ "$(readlink -f "$activation_package/home-files")" = "$(readlink -f "$home_files")" ] \
        || fail "the activation generation does not reference the evaluated home-files output"

      for executable in opencode zed eww alacritty atuin brightnessctl nixd; do
        [ -x "$activation_package/home-path/bin/$executable" ] \
          || fail "the activated Home Manager path is missing $executable"
      done
      [ -r "$home_files/.config/systemd/user/eww-osd.service" ] \
        || fail "generated Eww OSD user unit is missing"

      for relative in ${lib.escapeShellArgs retainedDesktopConfigFiles}; do
        target="$home_files/.config/$relative"
        [ -L "$target" ] || fail "retained config is not emitted as a link: .config/$relative"
      done

      for relative in ${lib.escapeShellArgs opencodeConfigFiles}; do
        target="$home_files/.config/$relative"
        [ -r "$target" ] || fail "generated OpenCode config is unreadable: .config/$relative"
        jq -e . "$target" >/dev/null || fail "generated OpenCode config is not valid JSON: .config/$relative"
      done

      opencode_config="$home_files/.config/opencode/opencode.json"
      jq -e '
        .model == "openai/gpt-5.5-fast"
        and .small_model == "openai/gpt-5.4-mini-fast"
        and .compaction == {auto: false, prune: false}
        and .snapshot == false
        and .permission == "allow"
        and .skills.paths == ["/home/becker/.config/opencode/skills"]
        and (.plugin | index("@cortexkit/aft-opencode@0.46.0") != null)
        and (.plugin | index("@tarquinen/opencode-dcp@latest") != null)
        and (.plugin | index("@cortexkit/opencode-magic-context@latest") != null)
        and (.plugin | index("opencode-pty@latest") != null)
        and (.plugin | index("@aeondave/opencode-background-agents@latest") != null)
        and (.plugin | any(startswith("@becker/opencode-agents-md-context@file:///nix/store/")))
        and .mcp["postgres-mcp"].type == "local"
        and .mcp["postgres-mcp"].enabled == true
        and .mcp["postgres-mcp"].timeout == 30000
        and .mcp["postgres-mcp"].environment.LOG_LEVEL == "warning"
        and (.mcp["postgres-mcp"].command[0] | endswith("/bin/postgres-mcp"))
        and .mcp["postgres-mcp"].command[1:] == [
          "--postgres",
          "postgresql://attune@127.0.0.1:54329/postgres",
          "--transport",
          "stdio",
          "--tool-filter",
          "codemode",
          "--audit-log",
          "/home/becker/.local/state/opencode/postgres-mcp-audit.jsonl"
        ]
        and .mcp["zig-docs"].type == "local"
        and .mcp["zig-docs"].enabled == true
        and .mcp["zig-docs"].timeout == 30000
        and (.mcp["zig-docs"].command[0] | endswith("/bin/zig-mcp"))
        and .mcp["zig-docs"].command[1:] == ["--doc-source", "local"]
      ' "$opencode_config" >/dev/null \
        || fail "generated OpenCode model, plugin, or MCP semantics changed"

      jq -se '.[0].plugin == .[1].plugin' \
        "$opencode_config" "$home_files/.config/opencode/tui.jsonc" >/dev/null \
        || fail "the OpenCode and TUI plugin stacks diverged"

      jq -e '
        .enabled == true
        and .debug == true
        and .pruneNotification == "detailed"
        and .pruneNotificationType == "chat"
        and .experimental == {allowSubAgents: true, customPrompts: false}
        and .compress.mode == "range"
        and .compress.permission == "allow"
        and .compress.minContextLimit == "25%"
        and .compress.maxContextLimit == "50%"
        and .compress.showCompression == true
        and .compress.summaryBuffer == true
        and .compress.nudgeFrequency == 1
        and .compress.iterationNudgeThreshold == 8
        and .compress.nudgeForce == "strong"
        and .compress.protectUserMessages == false
        and .manualMode == {automaticStrategies: true, enabled: false}
        and .strategies.deduplication.enabled == true
        and .strategies.purgeErrors == {enabled: true, turns: 4}
      ' "$home_files/.config/opencode/dcp.jsonc" >/dev/null \
        || fail "generated DCP behavior changed"

      jq -e '
        .enabled == true
        and .search_index == true
        and .semantic_search == true
        and .tool_surface == "recommended"
        and .configure_warnings_delivery == "toast"
        and .bash == {background: true, compress: true, enabled: true, rewrite: true}
        and .lsp == {auto_install: true, diagnostics_on_edit: true, python: "auto"}
      ' "$home_files/.config/cortexkit/aft.jsonc" >/dev/null \
        || fail "generated AFT behavior changed"

      jq -e '
        .enabled == true
        and .historian.model == "openai/gpt-5.4-mini-fast"
      ' "$home_files/.config/cortexkit/magic-context.jsonc" >/dev/null \
        || fail "generated Magic Context behavior changed"

      jq -e '
        .["magic-context"].forceToTop == true
        and .["magic-context"].order == -100
        and .["magic-context"].startCollapsed == false
        and .["magic-context"].collapsed == false
        and .["magic-context"].rememberCollapsed == true
        and .["magic-context"].header.label == "Magic Context"
        and .["magic-context"].sections == {
          dreamer: true,
          historian: true,
          memory: true,
          stats: true,
          status: true
        }
      ' "$home_files/.config/opencode/tui-preferences.jsonc" >/dev/null \
        || fail "generated OpenCode TUI preferences changed"

      for root in ${lib.escapeShellArgs forbiddenConfigRoots}; do
        target="$home_files/.config/$root"
        if [ -e "$target" ] || [ -L "$target" ]; then
          fail "removed config was emitted: .config/$root"
        fi
      done

      [ "$(git config --file "$home_files/.config/git/config" user.name)" = "becker63" ] \
        || fail "generated Git user.name changed"
      [ "$(git config --file "$home_files/.config/git/config" user.email)" = "johnsontaylor6320@gmail.com" ] \
        || fail "generated Git user.email changed"
      [ "$(git config --file "$home_files/.config/git/config" init.defaultBranch)" = "main" ] \
        || fail "generated Git default branch changed"
      [ "$(git config --file "$home_files/.config/git/config" pull.rebase)" = "true" ] \
        || fail "generated Git pull.rebase changed"

      grep -Fq 'get_workspace()' "$home_files/.bashrc" \
        || fail "generated Bash configuration lost the workspace prompt"
      grep -Fq 'atuin init bash' "$home_files/.bashrc" \
        || fail "generated Bash configuration lost Atuin integration"
      grep -Fq 'atuin init xonsh' '${../config/xonsh/rc.xsh}' \
        || fail "Xonsh configuration lost Atuin integration"

      [ "$(cat "$home_files/.npmrc")" = "prefix=/home/becker/.npm-global" ] \
        || fail "generated .npmrc changed"

      hotspot_script='${ewwHotspotScript}'
      [ -x "$hotspot_script" ] || fail "Eww power hotspot startup script is missing"
      grep -Fq 'eww ping' "$hotspot_script" \
        || fail "Eww power hotspot no longer waits for the daemon"
      grep -Fq 'eww open power_hotspot' "$hotspot_script" \
        || fail "Eww power hotspot is no longer opened at service startup"

      runtime='${opencodeRuntimePath}'
      wrapper='${opencodeWrapperPath}'
      [ -d "$runtime/lib/node_modules" ] || fail "OpenCode runtime node_modules output is missing"
      [ -x "$runtime/bin/zig-mcp" ] || fail "OpenCode runtime no longer exposes zig-mcp"
      [ -x "$wrapper/bin/opencode" ] || fail "OpenCode tooling wrapper is missing its public executable"
      [ -x "$wrapper/libexec/opencode" ] || fail "OpenCode tooling wrapper is missing its wrapped executable"
      [ -x "$wrapper/bin/postgres-mcp" ] || fail "OpenCode tooling wrapper no longer exposes postgres-mcp"
      grep -Fq 'direnv exec' "$wrapper/bin/opencode" \
        || fail "OpenCode wrapper lost direnv integration"

      echo "All $(jq '.checks | length' '${manifest}') evaluated Home Manager invariants and generated-artifact checks passed."
    '';
  };

  check =
    pkgs.runCommand "home-invariants-check"
      {
        nativeBuildInputs = [ preflight ];
      }
      ''
        home-invariants
        mkdir -p "$out"
        echo ok > "$out/result"
      '';
in
{
  package = preflight;
  inherit check;
}
