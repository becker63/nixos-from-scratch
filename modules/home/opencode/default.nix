{
  config,
  pkgs,
  lib,
  ...
}:

let
  instructions = import ./instructions.nix { inherit pkgs; };
  agentsPlugin = import ./agents-plugin.nix { inherit pkgs; };
  openspecSkills = import ./openspec-skills.nix { inherit pkgs; };
  tokenAudit = import ./token-audit.nix { inherit pkgs; };

  runtime = import ./runtime-wrapper.nix {
    inherit pkgs lib agentsPlugin;
    opencodeRuntimeSrc = ../../../packages/opencode-runtime;
  };

  settings = import ./settings.nix {
    inherit
      config
      pkgs
      instructions
      agentsPlugin
      runtime
      ;
  };
in
import ./activation.nix {
  inherit
    config
    pkgs
    lib
    runtime
    settings
    openspecSkills
    tokenAudit
    ;
}
