{
  config,
  hyprConfigFile,
  pkgs,
  # Both importers (outputs/perSystem/checks.nix and packages.nix's
  # check-suite wrappers) forward the portable package set so
  # factory-invariants can assert its exposure. Omitting it fails loudly:
  # switch-safety interpolates the factory-invariants marker, which fires
  # that check's missing-argument assert.
  portablePackages ? null,
  sourceRoot,
}:

let
  systemBuild = config.system.build.toplevel;

  # Owns the alacritty copy-buffer keybind family. LIGHT-BUILD (realizes a small derivation — safe to build).
  alacrittyCopybuffer = import ./alacritty-copybuffer.nix {
    inherit pkgs;
  };
  # Owns the gaming-stack family: steam-asahi, muvm, FEX, doctor, kvm group, gaming sysctls. EVAL-ASSERT + LIGHT-BUILD (binary smoke test).
  asahiGaming = import ./asahi-gaming.nix {
    inherit config pkgs;
  };
  # Owns the GDM greeter handoff contract on the generated closure. REBUILD-TIME (interpolates config.system.build.toplevel — NEVER build in this mission).
  greeter = import ./gdm-greeter-preflight.nix {
    inherit pkgs systemBuild;
  };
  # Owns the Hyprland GPU environment-variable contract. LIGHT-BUILD (realizes a small derivation — safe to build).
  hyprlandGpu = import ./hyprland-gpu-preflight.nix {
    inherit hyprConfigFile pkgs;
    hyprlandPackage = config.programs.hyprland.package;
    sessionVariables = config.environment.sessionVariables;
    lib = pkgs.lib;
  };
  # Owns the opencode context-stack end-to-end contract. LIGHT-BUILD (source-only mode — safe to build).
  opencodeContext = import ./opencode-context-stack-e2e.nix {
    inherit pkgs sourceRoot;
  };
  # Owns the core system invariant family: kernel pname, boot chain, firmware, UUIDs, swap tiering, groups, binfmt. EVAL-ASSERT layer + REBUILD-TIME preflight component (interpolates config.system.build.toplevel — NEVER build in this mission).
  systemInvariants = import ./system-invariants.nix {
    inherit
      config
      pkgs
      sourceRoot
      systemBuild
      ;
  };
  # Owns the Home Manager invariant table + opencode JSON semantics. EVAL-ASSERT table + LIGHT-BUILD (script part).
  homeInvariants = import ./home-invariants.nix {
    inherit pkgs;
    systemConfig = config;
  };
  # Owns the desktop OSD (eww/fnott) rendering contract. LIGHT-BUILD (realizes a small derivation — safe to build).
  desktopOsd = import ./desktop-osd-contract.nix {
    inherit pkgs sourceRoot;
  };
  # Owns the Factory/Droid/Jev wiring family: policy files, activation, routing literals, portable exposure. EVAL-ASSERT (trivial marker derivation).
  factoryInvariants = import ./factory-invariants.nix {
    inherit config pkgs portablePackages;
  };
  # Owns the xonsh rc semantics family. LIGHT-BUILD (realizes a small derivation — safe to build).
  xonshConfig = import ./xonsh-config.nix {
    inherit pkgs sourceRoot;
  };
  # Owns the pre-switch aggregate safety net: asserts every listed check
  # produced its result marker. REBUILD-TIME (interpolates
  # config.system.build.toplevel transitively via its members — NEVER build
  # in this mission).
  switchSafety = import ./switch-safety.nix {
    inherit pkgs;
    checks = {
      alacritty-copybuffer = alacrittyCopybuffer;
      asahi-gaming = asahiGaming;
      desktop-osd-contract = desktopOsd.check;
      # Trivial kernel-free marker, so the user's pre-switch net also
      # verifies the Factory wiring.
      factory-invariants = factoryInvariants;
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
