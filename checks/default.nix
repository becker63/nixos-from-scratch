{
  config,
  hyprConfigFile,
  pkgs,
  # Forwarded by the checks output wiring so factory-invariants can assert
  # the portable package exposure; check-suite wrapper imports may omit it.
  portablePackages ? null,
  sourceRoot,
}:

let
  systemBuild = config.system.build.toplevel;

  alacrittyCopybuffer = import ./alacritty-copybuffer.nix {
    inherit pkgs;
  };
  asahiGaming = import ./asahi-gaming.nix {
    inherit config pkgs;
  };
  greeter = import ./gdm-greeter-preflight.nix {
    inherit pkgs systemBuild;
  };
  hyprlandGpu = import ./hyprland-gpu-preflight.nix {
    inherit hyprConfigFile pkgs;
    hyprlandPackage = config.programs.hyprland.package;
    sessionVariables = config.environment.sessionVariables;
    lib = pkgs.lib;
  };
  opencodeContext = import ./opencode-context-stack-e2e.nix {
    inherit pkgs sourceRoot;
  };
  systemInvariants = import ./system-invariants.nix {
    inherit
      config
      pkgs
      sourceRoot
      systemBuild
      ;
  };
  homeInvariants = import ./home-invariants.nix {
    inherit pkgs;
    systemConfig = config;
  };
  desktopOsd = import ./desktop-osd-contract.nix {
    inherit pkgs sourceRoot;
  };
  factoryInvariants = import ./factory-invariants.nix {
    inherit config pkgs portablePackages;
  };
  xonshConfig = import ./xonsh-config.nix {
    inherit pkgs sourceRoot;
  };
  switchSafety = import ./switch-safety.nix {
    inherit pkgs;
    checks = {
      alacritty-copybuffer = alacrittyCopybuffer;
      asahi-gaming = asahiGaming;
      desktop-osd-contract = desktopOsd.check;
      gdm-greeter-preflight = greeter.check;
      home-invariants = homeInvariants.check;
      hyprland-gpu-preflight = hyprlandGpu.check;
      opencode-context-stack-e2e = opencodeContext.check;
      system-invariants = systemInvariants.check;
      xonsh-config = xonshConfig;
    };
  };
in
{
  inherit
    alacrittyCopybuffer
    asahiGaming
    desktopOsd
    factoryInvariants
    greeter
    homeInvariants
    hyprlandGpu
    opencodeContext
    switchSafety
    systemInvariants
    xonshConfig
    ;
}
