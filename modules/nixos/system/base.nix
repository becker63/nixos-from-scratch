{
  nixosBtwFlakeBuild ? false,
  pkgs,
  config,
  ...
}:

{
  assertions = [
    {
      assertion = nixosBtwFlakeBuild;
      message = ''
        Refusing to evaluate this Apple Silicon configuration outside its flake.

        This host must be rebuilt through the Nixverse node:

          sudo nixos-rebuild switch --flake /home/becker/nixos-from-scratch#nixos-btw

        Direct evaluation bypasses nixos-apple-silicon support, drops the
        linux-asahi/m1n1/U-Boot closure, and can create broken generic Linux
        boot entries.
      '';
    }
  ];

  boot = {
    loader.systemd-boot.enable = true;
    # Apple Silicon firmware/efivars can be touchy; allow bootctl to proceed
    # when EFI variables are not writable, since we already rely on the
    # removable-path install instead of mutating firmware boot entries.
    loader.systemd-boot.graceful = true;
    loader.efi.canTouchEfiVariables = false;

    # Attune ThinkCentre day-0 builds target x86_64 from this Asahi laptop.
    # Register qemu-user through binfmt so local Nix can execute x86_64
    # builder programs while evaluating installer and host closures.
    binfmt.emulatedSystems = [ "x86_64-linux" ];
  };

  boot.kernelModules = [
    "uhid"
    "hidp"
  ];

  # Keep interactive work responsive when concurrent builds briefly exceed RAM.
  # Swap tiering: RAM -> zram (priority 100, fast, compressed) -> 8 GiB disk
  # fallback (priority 10), so the kernel fills zram first and only spills to
  # the disk swapfile when the compressed tier is exhausted.
  # zramSwap.numDevices was removed upstream with a throwing shim; it stays
  # unset. Whole-attrset reads of config.zramSwap still evaluate that shim and
  # throw on the pinned nixpkgs; the individual options evaluate fine.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  # Disk fallback tier. `size` (MiB) makes the swap module create and mkswap
  # /var/lib/swapfile automatically at boot; the file need not pre-exist.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8192;
      priority = 10;
    }
  ];

  boot.kernel.sysctl = {
    # Prefer compressed swap over discarding useful filesystem cache.
    "vm.swappiness" = 100;
    # Swap readahead only adds decompression work for RAM-backed zram.
    "vm.page-cluster" = 0;
  };

  networking = {
    hostName = "nixos-btw";
    useNetworkd = false;
    firewall.allowPing = true;
    wireless.iwd = {
      enable = true;
      settings.Network.EnableNetworkConfiguration = true;
    };
  };

  services.resolved.enable = true;

  security.sudo.wheelNeedsPassword = false;

  # Declarative passwords come sops-encrypted from secrets/users.yaml; the age
  # private key lives outside the repo (~/.config/sops/age/keys.txt) and is
  # never committed. neededForUsers decrypts to /run/secrets-for-users before
  # user creation — the only point where declarative passwords apply at all,
  # since users.mutableUsers keeps its default true. The secret VALUES are
  # unchanged from the plaintext options they replace, so neither the live
  # logins nor a fresh install's declarative values differ.
  sops = {
    defaultSopsFile = ../../../secrets/users.yaml;
    age.keyFile = "/home/becker/.config/sops/age/keys.txt";
    secrets.becker_password.neededForUsers = true;
    secrets.root_password.neededForUsers = true;
  };

  users.users.becker = {
    isNormalUser = true;
    passwordFile = config.sops.secrets.becker_password.path;
    extraGroups = [
      "input"
      "video"
      "podman"
      "docker"
      "wheel"
      "storage"
    ];
    subUidRanges = [
      {
        startUid = 100000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 65536;
      }
    ];
    shell = "${pkgs.xonsh}/bin/xonsh";
  };

  # No initialPasswordFile option exists upstream; passwordFile is the closest
  # declarative equivalent and (like initialPassword) only applies at user
  # creation on this host's default mutableUsers setting.
  users.users.root.passwordFile = config.sops.secrets.root_password.path;

  nix = {
    settings = {
      builders-use-substitutes = true;
      extra-platforms = [ "aarch64-linux" ];
      require-sigs = false;
      trusted-users = [
        "becker"
        "@wheel"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      keep-outputs = true;
      keep-derivations = true;

      # Official nixos-apple-silicon Cachix binary cache from:
      # https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/binary-cache.md
      extra-substituters = [ "https://nixos-apple-silicon.cachix.org" ];
      extra-trusted-public-keys = [
        "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;
  programs.nix-ld.enable = true;

  environment.shells = [ "${pkgs.xonsh}/bin/xonsh" ];
  environment.etc."distrobox/distrobox.conf".text = ''
    container_additional_volumes="/nix/store:/nix/store:ro /etc/profiles/per-user:/etc/profiles/per-user:ro /etc/static/profiles/per-user:/etc/static/profiles/per-user:ro"
  '';

  # Podman stays explicitly off; Docker is the container runtime on this host.
  virtualisation.podman.enable = false;
  virtualisation.docker.enable = true;

  system.stateVersion = "25.05";
}
