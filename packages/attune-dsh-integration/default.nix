# A separately owned, minimal local integration profile for the pinned DeepSeek
# Harness (owner `finish-native-review-integration`, VAL-SUB-014).
#
# It builds ONE dedicated DSH profile — the pinned `web` composition plus exactly
# the two research-surface plugins the integration needs (Live Maze and Research
# Graph) at their exact compatible versions — together with the declared
# configuration that points the pinned session persistence and the supported
# SQLite session-query index at a dedicated integration store on loopback 3180.
#
# Nothing here touches the existing `dsh` package, the personal `~/.dsh`
# profile, its sessions, its model defaults or its credentials, and no flake
# input, kernel or system closure is changed. The launcher materializes the
# profile under a dedicated `$XDG_STATE_HOME/attune-dsh-integration` home and
# execs the pinned `dsh` binary with `--profile attune`.
{
  lib,
  dsh,
  buildNpmPackage,
  stdenv,
  makeWrapper,
  nodejs_24,
  coreutils,
  gnused,
  diffutils,
  cacert,
}:

let
  # The pinned plugin closure of the minimal integration profile. Only the two
  # research-surface plugins are dependencies; the host bundles
  # (`@deepseek-ai/dsh-base`, `@deepseek-ai/dsh-web-app`) resolve from the pinned
  # `dsh` installation, exactly as the Harness resolves them for its shipped
  # profiles. `package-lock.json` and `npmDepsHash` fix the whole closure.
  pluginClosure = buildNpmPackage {
    pname = "attune-dsh-integration-profile";
    version = "0.2.0-rc.2";
    nodejs = nodejs_24;
    src = lib.fileset.toSource {
      root = ./profile;
      fileset = lib.fileset.unions [
        ./profile/package.json
        ./profile/package-lock.json
      ];
    };
    npmDepsHash = "sha256-svlQ6f730U7bgHJOKy8M8N3rkik1WCs3j+5kSxPmn5s=";
    npmFlags = [
      "--ignore-scripts"
      "--legacy-peer-deps"
    ];
    dontNpmBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/attune-dsh-integration/profile"
      cp -R node_modules "$out/share/attune-dsh-integration/profile/node_modules"
      runHook postInstall
    '';
    meta = {
      description = "Pinned plugin closure of the dedicated Attune DSH integration profile";
      license = lib.licenses.mit;
    };
  };
in
stdenv.mkDerivation {
  pname = "attune-dsh-integration";
  version = "0.2.0-rc.2";

  nativeBuildInputs = [ makeWrapper ];

  buildCommand = ''
    mkdir -p "$out/share/attune-dsh-integration/profile" "$out/bin"

    cp ${./profile/package.json} "$out/share/attune-dsh-integration/profile/package.json"
    cp ${./profile/pnpm-workspace.yaml} "$out/share/attune-dsh-integration/profile/pnpm-workspace.yaml"
    cp ${./profile/cordis.patch.yml.in} "$out/share/attune-dsh-integration/profile/cordis.patch.yml.in"
    cp -R ${pluginClosure}/share/attune-dsh-integration/profile/node_modules \
      "$out/share/attune-dsh-integration/profile/node_modules"

    install -m 0755 ${./launcher.sh} "$out/bin/attune-dsh-integration"
    wrapProgram "$out/bin/attune-dsh-integration" \
      --set ATTUNE_DSH_INTEGRATION_SHARE "$out/share/attune-dsh-integration" \
      --set ATTUNE_DSH_INTEGRATION_DSH "${dsh}" \
      --prefix PATH : ${lib.makeBinPath [ nodejs_24 coreutils gnused diffutils ]} \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt

    # The verification runs INSIDE the build, because a derivation that sets
    # `buildCommand` runs no phase list, so an `installCheckPhase` would never
    # execute. It composes the dedicated profile offline through the pinned
    # host — the web surface plus the two research plugins, with the declared
    # loopback configuration and the dedicated store — and fails the build
    # loudly if any of that is untrue. No provider, no model call. The launcher
    # runs with an EMPTY environment, so the check also fails if it depends on
    # anything outside this package and its pinned inputs.
    check=$(mktemp -d)
    export HOME="$check/home"
    export XDG_STATE_HOME="$check/state"
    mkdir -p "$HOME"

    env -i HOME="$HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
      "$out/bin/attune-dsh-integration" --dump-config > "$check/dump.yml"
    grep -q '^# == @deepseek-ai/dsh-web-app' "$check/dump.yml"
    grep -q '^# == dsh-maze' "$check/dump.yml"
    grep -q '^# == @benz-ai-x/dsh-research-graph' "$check/dump.yml"
    grep -q 'port: 3180' "$check/dump.yml"

    profile="$XDG_STATE_HOME/attune-dsh-integration/dsh-home/profiles/attune"
    test -f "$profile/package.json"
    # The plugin closure is materialized INSIDE the profile: the Harness
    # resolver matches an imported module's real path against the profile
    # directory, so a closure linked out of the store would not resolve.
    test -d "$profile/node_modules"
    test ! -L "$profile/node_modules"
    test -f "$profile/node_modules/dsh-maze/package.json"
    test -f "$profile/node_modules/@benz-ai-x/dsh-research-graph/package.json"
    test -f "$profile/cordis.patch.yml"
    grep -q "root: '$XDG_STATE_HOME/attune-dsh-integration/store/sessions'" "$profile/cordis.patch.yml"
    grep -q 'port: 3180' "$profile/cordis.patch.yml"

    # The launcher is idempotent: a second invocation changes no profile byte.
    before=$(find "$profile" -type f -exec sha256sum {} + | sort | sha256sum)
    env -i HOME="$HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
      "$out/bin/attune-dsh-integration" --dump-config > "$check/dump-2.yml"
    after=$(find "$profile" -type f -exec sha256sum {} + | sort | sha256sum)
    test "$before" = "$after"

    # The personal Harness home is never created, read or written, and the
    # dedicated home is the only one the launcher materializes.
    test ! -e "$HOME/.dsh"
    test -d "$XDG_STATE_HOME/attune-dsh-integration/dsh-home"
    rm -rf "$check"
    unset HOME XDG_STATE_HOME
  '';

  meta = {
    description = "Dedicated local DSH integration profile (web + Live Maze + Research Graph) with a private store";
    license = lib.licenses.mit;
    mainProgram = "attune-dsh-integration";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
