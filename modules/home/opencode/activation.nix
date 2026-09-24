{
  config,
  pkgs,
  lib,
  runtime,
  settings,
  openspecSkills,
  tokenAudit,
}:

{
  home.sessionPath = [ "${config.home.homeDirectory}/.npm-global/bin" ];

  home.file.".npmrc".text = ''
    prefix=${config.home.homeDirectory}/.npm-global
  '';

  home.activation.installOpenCodeRuntime = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export HOME="${config.home.homeDirectory}"
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
      ]
    }:$PATH"

    rm -rf \
      "${config.home.homeDirectory}/.cache/opencode/packages/@cortexkit/opencode-magic-context@file:"* \
      "${config.home.homeDirectory}/.cache/opencode/packages/@slkiser/opencode-quota" \
      "${config.home.homeDirectory}/.cache/opencode/packages/@slkiser/opencode-quota@latest"

    mkdir -p "${config.home.homeDirectory}/.config/opencode/node_modules"
    for packageName in ${
      lib.concatMapStringsSep " " (pkg: "\"${pkg}\"") runtime.opencodeRuntimeNodeModulePackages
    }; do
      target="${config.home.homeDirectory}/.config/opencode/node_modules/$packageName"
      source="${runtime.opencodeRuntime}/lib/node_modules/$packageName"
      mkdir -p "$(dirname "$target")"
      rm -rf "$target"
      ln -s "$source" "$target"
    done

    mkdir -p "${config.home.homeDirectory}/.cache/opencode/packages"
    for cacheName in ${
      lib.concatMapStringsSep " " (pkg: "\"${pkg}\"") runtime.opencodeRuntimeCachePackages
    }; do
      target="${config.home.homeDirectory}/.cache/opencode/packages/$cacheName"
      source="${runtime.opencodeRuntime}/cache-packages/$cacheName"
      mkdir -p "$(dirname "$target")"
      rm -rf "$target"
      ln -s "$source" "$target"
    done

    opencodeKv="${config.home.homeDirectory}/.local/state/opencode/kv.json"
    mkdir -p "$(dirname "$opencodeKv")"
    if [ ! -s "$opencodeKv" ]; then
      printf '{}\n' > "$opencodeKv"
    fi
    kvTmp="$(mktemp)"
    "${pkgs.jq}/bin/jq" '
      .sidebar = (.sidebar // "auto")
      | .plugin_enabled = (.plugin_enabled // {})
      | .plugin_enabled |= del(
          .["opencode-magic-context-canary"],
          .["opencode-magic-context-sidebar"],
          .["opencode-magic-context:opencode-magic-context-canary"],
          .["opencode-magic-context:opencode-magic-context-sidebar"],
          .["opencode-magic-context:opencode-magic-context-presence"],
          .["opencode-magic-context:1"],
          .["opencode-magic-context:2"]
        )
      | .plugin_enabled["internal:sidebar-context"] = true
      | .plugin_enabled["opencode-magic-context"] = true
    ' "$opencodeKv" > "$kvTmp"
    mv "$kvTmp" "$opencodeKv"

    opencodeModelState="${config.home.homeDirectory}/.local/state/opencode/model.json"
    mkdir -p "$(dirname "$opencodeModelState")"
    if [ ! -s "$opencodeModelState" ]; then
      printf '{"recent":[],"favorite":[],"variant":{}}\n' > "$opencodeModelState"
    fi
    modelStateTmp="$(mktemp)"
    "${pkgs.jq}/bin/jq" '
      .recent = (.recent // [])
      | .favorite = (.favorite // [])
      | .variant = (.variant // {})
      | .variant["openai/gpt-5.5"] = "high"
      | .variant["openai/gpt-5.5-fast"] = "high"
    ' "$opencodeModelState" > "$modelStateTmp"
    mv "$modelStateTmp" "$opencodeModelState"
  '';

  xdg.configFile =
    openspecSkills.xdgConfigFiles // tokenAudit.xdgConfigFiles // settings.xdgConfigFiles;

  home.packages = [
    runtime.opencodeRuntime
    runtime.opencodeWithTooling
  ];
}
