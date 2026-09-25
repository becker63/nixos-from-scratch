{
  config,
  pkgs,
  sourceRoot,
  systemBuild,
}:

let
  inherit (pkgs) lib;

  expect = condition: message: lib.optional (!condition) message;

  packageName = lib.getName;

  systemPackageNames = map packageName config.environment.systemPackages;
  graphicsPackageNames = map packageName config.hardware.graphics.extraPackages;

  m1n1 = config.system.build.m1n1;
  peripheralFirmwareSource = "${sourceRoot}/firmware";

  # Matches users.users.becker.extraGroups exactly; gaming.nix legitimately
  # adds kvm for /dev/kvm access.
  expectedGroups = [
    "docker"
    "input"
    "kvm"
    "podman"
    "storage"
    "video"
    "wheel"
  ];
  actualGroups = lib.sort builtins.lessThan config.users.users.becker.extraGroups;

  expectedLogindSettings = {
    HandleHibernateKey = "ignore";
    HandleHibernateKeyLongPress = "ignore";
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleSuspendKey = "ignore";
    HandleSuspendKeyLongPress = "ignore";
    LidSwitchIgnoreInhibited = "yes";
  };
  logindSettings = config.services.logind.settings.Login;

  isEmptyStringArray =
    value:
    builtins.isAttrs value
    && value ? type
    && value ? value
    && toString value.type == "as"
    && value.value == [ ];

  protectedGdmMediaKeys = [
    "hibernate"
    "hibernate-static"
    "suspend"
    "suspend-static"
  ];

  gdmPolicyDatabases = builtins.filter builtins.isAttrs config.programs.dconf.profiles.gdm.databases;
  hasLockedGdmPowerPolicy = lib.any (
    database:
    let
      settings = database.settings or { };
      mediaKeys = settings."org/gnome/settings-daemon/plugins/media-keys" or { };
      power = settings."org/gnome/settings-daemon/plugins/power" or { };
    in
    (database.lockAll or false)
    && lib.all (
      key: builtins.hasAttr key mediaKeys && isEmptyStringArray mediaKeys.${key}
    ) protectedGdmMediaKeys
    && (power.power-button-action or null) == "nothing"
  ) gdmPolicyDatabases;

  portalNames = map packageName config.xdg.portal.extraPortals;

  removedPackageNames = [
    "powerstat"
    "wgetpaste"
  ];

  evaluationFailures = lib.flatten [
    (expect (
      pkgs.stdenv.hostPlatform.system == "aarch64-linux"
    ) "the package set must target aarch64-linux")
    (expect (
      config.nixpkgs.hostPlatform.system == "aarch64-linux"
    ) "the NixOS host platform must remain aarch64-linux")
    (expect (config.networking.hostName == "nixos-btw") "the host name must remain nixos-btw")
    (expect (config.system.stateVersion == "25.05") "the NixOS state version must remain 25.05")
    # Kernel-pname defense-in-depth: checks/asahi-gaming.nix repeats this
    # assert to guard the gaming stack; keep both in sync.
    (expect (
      config.boot.kernelPackages.kernel.pname == "linux-asahi"
    ) "the boot kernel must remain linux-asahi")
    (expect (lib.hasSuffix "-boot.bin" (toString m1n1)) "the Apple m1n1 boot payload must remain part of the system build")
    (expect config.boot.loader.systemd-boot.enable "systemd-boot must remain enabled")
    (expect config.boot.loader.systemd-boot.graceful "systemd-boot graceful mode must remain enabled for Apple firmware")
    (expect (
      !config.boot.loader.efi.canTouchEfiVariables
    ) "the boot loader must not write Apple EFI variables")

    (expect (
      config.fileSystems."/".device == "/dev/disk/by-uuid/04e66dd3-e3f3-4ffe-92d3-a7d38c167d31"
    ) "the root filesystem UUID changed")
    (expect (config.fileSystems."/".fsType == "ext4") "the root filesystem must remain ext4")
    (expect (
      config.fileSystems."/boot".device == "/dev/disk/by-uuid/4796-181C"
    ) "the /boot filesystem UUID changed")
    (expect (config.fileSystems."/boot".fsType == "vfat") "the /boot filesystem must remain vfat")
    (expect (lib.all (option: builtins.elem option config.fileSystems."/boot".options) [
      "dmask=0022"
      "fmask=0022"
    ]) "the /boot permission masks changed")

    # Swap tiering: RAM -> zram (priority 100) -> disk swapfile (priority 10).
    # These asserts read the zramSwap leaf options individually: upstream
    # removed zramSwap.numDevices with a throwing shim, so any whole-attrset
    # read of config.zramSwap would abort evaluation on the pinned nixpkgs.
    (expect config.zramSwap.enable "zram swap must remain enabled")
    (expect (config.zramSwap.algorithm == "zstd") "zram must keep the zstd compression algorithm")
    (expect (config.zramSwap.memoryPercent == 50) "zram must remain sized at 50 percent of RAM")
    (expect (config.zramSwap.priority == 100) "zram swap must keep priority 100")
    (expect (
      map (sw: {
        inherit (sw) device priority size;
      }) config.swapDevices == [
        {
          device = "/var/lib/swapfile";
          priority = 10;
          size = 8192;
        }
      ]
    ) "the disk swap fallback must be exactly the 8 GiB /var/lib/swapfile at priority 10")
    (expect (lib.all (
      sw: config.zramSwap.priority > sw.priority
    ) config.swapDevices) "zram swap must outrank every disk swap device")
    (expect (
      config.boot.kernel.sysctl."vm.swappiness" == 100
    ) "vm.swappiness must remain 100 to prefer the compressed zram tier")
    (expect (
      config.boot.kernel.sysctl."vm.page-cluster" == 0
    ) "vm.page-cluster must remain 0 for RAM-backed zram readahead")

    (expect config.hardware.asahi.enable "nixos-apple-silicon support must remain enabled")
    (expect config.hardware.asahi.extractPeripheralFirmware "Asahi peripheral firmware extraction must remain enabled")
    (expect (
      config.hardware.asahi.peripheralFirmwareDirectory != null
    ) "the Asahi peripheral firmware extraction source must remain configured")
    (expect (builtins.pathExists "${peripheralFirmwareSource}/all_firmware.tar.gz") "the Apple firmware archive is missing")
    (expect (builtins.pathExists "${peripheralFirmwareSource}/kernelcache.release.mac14g") "the mac14g kernelcache used for Apple firmware extraction is missing")
    (expect config.hardware.asahi.setupAsahiSound "Asahi speaker/audio setup must remain enabled")
    (expect config.hardware.graphics.enable "hardware graphics acceleration must remain enabled")
    (map (name: expect (builtins.elem name graphicsPackageNames) "hardware graphics is missing ${name}")
      [
        "libva"
        "libva-utils"
        "mesa"
      ]
    )
    (expect (
      config.environment.sessionVariables.LIBVA_DRIVER_NAME or null == "asahi"
    ) "LIBVA_DRIVER_NAME must remain asahi")
    (expect (
      config.environment.sessionVariables.MESA_LOADER_DRIVER_OVERRIDE or null == "asahi"
    ) "MESA_LOADER_DRIVER_OVERRIDE must remain asahi")
    (expect (
      config.environment.sessionVariables.VDPAU_DRIVER or null == "va_gl"
    ) "VDPAU_DRIVER must remain va_gl")
    (expect (
      config.environment.sessionVariables.QT_QPA_PLATFORM or null == "wayland"
    ) "QT_QPA_PLATFORM must remain wayland")
    (expect (
      config.environment.sessionVariables.LV2_PATH or null == "${pkgs.asahi-audio}/lib/lv2"
    ) "LV2_PATH must continue to expose the Asahi audio plugins")

    (expect config.services.pipewire.enable "PipeWire must remain enabled")
    (expect config.services.pipewire.alsa.enable "PipeWire ALSA support must remain enabled")
    (expect config.services.pipewire.alsa.support32Bit "PipeWire 32-bit ALSA support must remain enabled")
    (expect config.services.pipewire.pulse.enable "PipeWire PulseAudio compatibility must remain enabled")
    (expect config.services.pipewire.wireplumber.enable "WirePlumber must remain enabled")
    (expect (!config.services.pipewire.jack.enable) "PipeWire JACK support must remain disabled")

    (expect config.hardware.bluetooth.enable "Bluetooth must remain enabled")
    (expect config.hardware.bluetooth.powerOnBoot "Bluetooth must remain powered on at boot")
    (expect config.services.blueman.enable "Blueman must remain enabled")

    (expect (!config.networking.useNetworkd) "networkd must remain disabled for the IWD setup")
    (expect config.networking.wireless.iwd.enable "IWD must remain enabled")
    (expect (config.networking.wireless.iwd.settings.Network.EnableNetworkConfiguration or false
    ) "IWD network configuration must remain enabled")
    (expect config.services.resolved.enable "systemd-resolved must remain enabled")
    (expect config.services.openssh.enable "OpenSSH must remain enabled")
    (expect config.services.openssh.openFirewall "OpenSSH must continue to open its configured firewall port")
    (expect (builtins.elem 22 config.networking.firewall.allowedTCPPorts) "TCP port 22 must remain allowed through the firewall")
    (expect config.services.tailscale.enable "Tailscale must remain enabled")
    (expect (
      !config.services.tailscale.openFirewall
    ) "Tailscale must not broaden the firewall implicitly")
    (expect config.networking.firewall.enable "the NixOS firewall must remain enabled")
    (expect config.networking.firewall.allowPing "the firewall must continue to allow ping")

    (expect config.users.users.becker.isNormalUser "becker must remain a normal user")
    (expect (
      actualGroups == expectedGroups
    ) "becker's docker/input/kvm/podman/storage/video/wheel group set changed")
    (expect (
      toString config.users.users.becker.shell == "${pkgs.xonsh}/bin/xonsh"
    ) "becker's login shell must remain Xonsh")
    # Password PATHS only: these asserts pin where the declarative passwords
    # come from, never their content (secret values never enter evaluation).
    (expect (
      config.users.users.becker.hashedPasswordFile == config.sops.secrets.becker_password.path
    ) "becker's declarative password must come from the sops becker_password secret")
    (expect (
      config.users.users.root.hashedPasswordFile == config.sops.secrets.root_password.path
    ) "root's declarative password must come from the sops root_password secret")
    (expect config.virtualisation.docker.enable "Docker must remain enabled")
    (expect (!config.virtualisation.podman.enable) "Podman must remain disabled")
    (expect (
      !config.security.sudo.wheelNeedsPassword
    ) "passwordless sudo for wheel must remain enabled")
    (expect (
      config.boot.binfmt.emulatedSystems == [ "x86_64-linux" ]
    ) "x86_64-linux binary emulation must remain enabled")
    (expect (
      config.users.users.becker.subUidRanges == [
        {
          count = 65536;
          startUid = 100000;
        }
      ]
    ) "becker's subordinate UID range changed")
    (expect (
      config.users.users.becker.subGidRanges == [
        {
          count = 65536;
          startGid = 100000;
        }
      ]
    ) "becker's subordinate GID range changed")

    (expect (builtins.elem "https://nixos-apple-silicon.cachix.org" config.nix.settings.extra-substituters) "the Apple Silicon binary cache substituter must remain configured")
    (expect (builtins.elem "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20=" config.nix.settings.extra-trusted-public-keys) "the Apple Silicon binary cache signing key must remain trusted")
    (expect (lib.all (feature: builtins.elem feature config.nix.settings.experimental-features) [
      "flakes"
      "nix-command"
    ]) "flakes and nix-command must remain enabled")
    (expect (lib.all (user: builtins.elem user config.nix.settings.trusted-users) [
      "@wheel"
      "becker"
      "root"
    ]) "the trusted Nix users changed")
    (expect config.nix.settings.keep-outputs "Nix must continue to keep derivation outputs")
    (expect config.nix.settings.keep-derivations "Nix must continue to keep derivations")

    (expect config.services.gnome.gnome-keyring.enable "GNOME Keyring must remain enabled")
    (expect config.security.pam.services.login.enableGnomeKeyring "GNOME Keyring must remain enabled for login PAM")
    (expect config.security.pam.services.gdm.enableGnomeKeyring "GNOME Keyring must remain enabled for GDM PAM")

    (expect config.programs.hyprland.enable "Hyprland must remain enabled")
    (expect config.services.displayManager.gdm.enable "GDM must remain enabled")
    (expect config.services.displayManager.gdm.debug "GDM debug logging must remain enabled for greeter diagnosis")
    (expect (builtins.elem "/share/gnome-session" config.environment.pathsToLink) "the GNOME greeter session path must remain linked into the system profile")
    (expect config.xdg.portal.enable "XDG desktop portals must remain enabled")
    (expect (!config.xdg.portal.wlr.enable) "the generic wlroots portal must remain disabled")
    (expect (builtins.elem "xdg-desktop-portal-gtk" portalNames) "the GTK desktop portal must remain available")
    (expect (builtins.elem "xdg-desktop-portal-hyprland" portalNames) "the Hyprland desktop portal must remain available")

    (map (
      name:
      expect (
        builtins.hasAttr name logindSettings && logindSettings.${name} == expectedLogindSettings.${name}
      ) "logind ${name} must remain ${expectedLogindSettings.${name}}"
    ) (builtins.attrNames expectedLogindSettings))
    (expect hasLockedGdmPowerPolicy "GDM must keep locked suspend, hibernate, and power-button shortcuts disabled")

    (expect (
      config.systemd.services.nix-store-gc.serviceConfig.Type == "oneshot"
    ) "the Nix store garbage collector must remain a oneshot service")
    (expect (
      config.systemd.timers.nix-store-gc.wantedBy == [ "timers.target" ]
    ) "the Nix store garbage collector timer must remain enabled")
    (expect (
      config.systemd.timers.nix-store-gc.timerConfig.OnCalendar == "Sun *-*-* 03:00:00"
    ) "the weekly Nix store garbage collection schedule changed")
    (expect config.systemd.timers.nix-store-gc.timerConfig.Persistent "the Nix store garbage collection timer must remain persistent")
    (expect (
      config.systemd.timers.nix-store-gc.timerConfig.RandomizedDelaySec == "30m"
    ) "the Nix store garbage collection randomized delay changed")

    (map (
      name:
      expect (
        !builtins.elem name systemPackageNames
      ) "removed package ${name} returned to environment.systemPackages"
    ) removedPackageNames)
  ];

  invariantsHold = builtins.deepSeq evaluationFailures (evaluationFailures == [ ]);
  evaluationFailureMessage = ''
    The nixos-btw switch-safety invariants failed:
    ${lib.concatMapStringsSep "\n" (message: "  - ${message}") evaluationFailures}
  '';
  guard =
    value:
    assert lib.assertMsg invariantsHold evaluationFailureMessage;
    value;

  preflight = guard (
    pkgs.writeShellApplication {
      name = "system-invariants-preflight";
      runtimeInputs = with pkgs; [
        coreutils
        findutils
        gnugrep
        jq
      ];
      text = ''
        set -euo pipefail

        fail() {
          echo "FAIL: $*" >&2
          exit 1
        }

        require_path() {
          [ -e "$1" ] || fail "missing generated path: $1"
        }

        system_build='${systemBuild}'
        m1n1='${m1n1}'
        require_path "$system_build/boot.json"
        require_path "$system_build/kernel"
        require_path "$system_build/initrd"
        require_path "$system_build/etc/fstab"
        require_path "$system_build/etc/systemd/logind.conf"

        jq -e \
          '.["org.nixos.bootspec.v1"].system == "aarch64-linux" and has("org.nixos.systemd-boot")' \
          "$system_build/boot.json" >/dev/null \
          || fail "boot.json lost its aarch64-linux systemd-boot metadata"

        [ -s "$m1n1" ] || fail "the generated Apple m1n1 boot.bin payload is missing"
        case "$m1n1" in
          /nix/store/*-boot.bin) ;;
          *) fail "the Apple boot payload is not a boot.bin store output: $m1n1" ;;
        esac

        kernel_target="$(readlink -f "$system_build/kernel")"
        case "$kernel_target" in
          /nix/store/*-linux-asahi-*/Image) ;;
          *) fail "generated kernel is not linux-asahi: $kernel_target" ;;
        esac

        initrd_target="$(readlink -f "$system_build/initrd")"
        case "$initrd_target" in
          /nix/store/*-initrd-linux-asahi-*/initrd) ;;
          *) fail "generated initrd is not for linux-asahi: $initrd_target" ;;
        esac

        require_path "$system_build/firmware"
        require_path "$system_build/firmware/apple/tpmtfw-j413.bin.zst"

        grep -Eq '^/dev/disk/by-uuid/04e66dd3-e3f3-4ffe-92d3-a7d38c167d31[[:space:]]+/[[:space:]]+ext4[[:space:]]' \
          "$system_build/etc/fstab" || fail "generated fstab lost the root filesystem UUID"
        grep -Eq '^/dev/disk/by-uuid/4796-181C[[:space:]]+/boot[[:space:]]+vfat[[:space:]]' \
          "$system_build/etc/fstab" || fail "generated fstab lost the /boot filesystem UUID"

        for setting in \
          HandleHibernateKey=ignore \
          HandleHibernateKeyLongPress=ignore \
          HandleLidSwitch=ignore \
          HandleLidSwitchDocked=ignore \
          HandleLidSwitchExternalPower=ignore \
          HandleSuspendKey=ignore \
          HandleSuspendKeyLongPress=ignore \
          LidSwitchIgnoreInhibited=yes
        do
          grep -Fx "$setting" "$system_build/etc/systemd/logind.conf" >/dev/null \
            || fail "generated logind.conf lost $setting"
        done

        for relative_path in \
          system/display-manager.service \
          system/bluetooth.target.wants/bluetooth.service \
          system/multi-user.target.wants/docker.service \
          system/multi-user.target.wants/iwd.service \
          system/multi-user.target.wants/sshd.service \
          system/multi-user.target.wants/tailscaled.service \
          system/sysinit.target.wants/systemd-resolved.service \
          user/pipewire-pulse.service \
          user/pipewire.service \
          user/pipewire.service.wants/wireplumber.service
        do
          require_path "$system_build/etc/systemd/$relative_path"
        done

        require_path "$system_build/sw/bin/Hyprland"
        require_path "$system_build/sw/bin/gdm"
        require_path "$system_build/sw/share/xdg-desktop-portal/portals/gtk.portal"
        require_path "$system_build/sw/share/xdg-desktop-portal/portals/hyprland.portal"

        home_manager_unit="$system_build/etc/systemd/system/home-manager-becker.service"
        require_path "$home_manager_unit"
        grep -Fx 'User=becker' "$home_manager_unit" >/dev/null \
          || fail "the generated Home Manager unit no longer runs as becker"
        grep -F 'Environment="HOME_MANAGER_BACKUP_EXT=backup"' "$home_manager_unit" >/dev/null \
          || fail "the generated Home Manager unit lost its backup extension"
        grep -F 'ExecStart=' "$home_manager_unit" \
          | grep -F '${config.home-manager.users.becker.home.activationPackage}' >/dev/null \
          || fail "the generated Home Manager unit no longer activates the evaluated generation"

        for executable in powerstat wgetpaste; do
          [ ! -e "$system_build/sw/bin/$executable" ] \
            || fail "removed executable returned to the target system: $executable"
        done

        echo "ok: nixos-btw evaluation and generated-system invariants are preserved"
      '';
    }
  );

  check = guard (
    pkgs.runCommand "system-invariants-check" { } ''
      set -euo pipefail
      ${preflight}/bin/system-invariants-preflight
      mkdir -p "$out"
      echo ok > "$out/result"
    ''
  );
in
{
  package = preflight;
  inherit check;
}
