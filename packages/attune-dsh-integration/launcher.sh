#!/bin/sh
# The launcher of the dedicated Attune DSH integration profile (VAL-SUB-014).
#
# It boots the pinned DeepSeek Harness's own `web` composition — the profile that
# carries the chat/trajectory surface plus the Live Maze and Research Graph
# tabs — from a DEDICATED Harness home, with a dedicated store. The personal
# `~/.dsh` is never read or written: the profile manifest, the pinned plugin
# closure and the declared configuration all come from this package, and only
# the dedicated home under `$XDG_STATE_HOME/attune-dsh-integration` is created.
#
# The wrapper sets ATTUNE_DSH_INTEGRATION_SHARE (this package's share tree) and
# ATTUNE_DSH_INTEGRATION_DSH (the pinned dsh installation). Override the
# dedicated home or store with ATTUNE_DSH_HOME / ATTUNE_DSH_STORE; the personal
# home is never a valid target.
set -eu

profile_name=attune
state_home=${XDG_STATE_HOME:-${HOME:?HOME is unset}/.local/state}
dsh_home=${ATTUNE_DSH_HOME:-$state_home/attune-dsh-integration/dsh-home}
store=${ATTUNE_DSH_STORE:-$state_home/attune-dsh-integration/store}
share=${ATTUNE_DSH_INTEGRATION_SHARE:?the wrapper must set ATTUNE_DSH_INTEGRATION_SHARE}
dsh_bin=${ATTUNE_DSH_INTEGRATION_DSH:?the wrapper must set ATTUNE_DSH_INTEGRATION_DSH}/bin/dsh

case "$dsh_home" in
  "$HOME/.dsh" | "$HOME/.dsh/"*)
    echo "attune-dsh-integration: refusing to use the personal Harness home $dsh_home" >&2
    exit 2
    ;;
esac

profile_dir=$dsh_home/profiles/$profile_name
mkdir -p "$dsh_home/profiles" "$profile_dir"

# The profile manifest and the pnpm settings are refreshed from the package when
# they differ; the user's own patch layer is created once and never overwritten.
for file in package.json pnpm-workspace.yaml; do
  if [ ! -e "$profile_dir/$file" ] || ! cmp -s "$share/profile/$file" "$profile_dir/$file"; then
    cp "$share/profile/$file" "$profile_dir/$file"
  fi
done
if [ ! -e "$profile_dir/cordis.patch.yml" ]; then
  sed "s|@STORE@|$store|g" "$share/profile/cordis.patch.yml.in" > "$profile_dir/cordis.patch.yml"
fi

# The plugin closure is MATERIALIZED inside the profile rather than linked to the
# store: the Harness's profile resolver matches an imported module's real path
# against the profile directory, so a linked closure would sit outside the
# profile and the plugins' own peer imports would fail to resolve. The stamp
# makes the copy idempotent and refreshes it when the package changes.
stamp=$profile_dir/.attune-plugin-closure
closure=$share/profile/node_modules
if [ ! -d "$profile_dir/node_modules" ] || [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$closure" ]; then
  if [ -d "$profile_dir/node_modules" ] && [ ! -L "$profile_dir/node_modules" ]; then
    rm -rf "$profile_dir/node_modules"
  fi
  cp -R "$closure" "$profile_dir/node_modules"
  chmod -R u+w "$profile_dir/node_modules"
  printf '%s\n' "$closure" > "$stamp"
fi

exec env DSH_HOME="$dsh_home" "$dsh_bin" --profile "$profile_name" "$@"
