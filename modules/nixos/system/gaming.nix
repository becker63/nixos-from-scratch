{
  config,
  lib,
  pkgs,
  ...
}:

let
  guestDbus = pkgs.writeShellScript "steam-asahi-guest-dbus" ''
    set -eu
    mkdir -p /run/dbus
    if [ ! -S /run/dbus/system_bus_socket ]; then
      ${pkgs.dbus}/bin/dbus-daemon --system --fork
    fi
  '';

  # Steam treats the presence of a system bus as its network-state signal even
  # though passt already provides working guest networking. Start only D-Bus,
  # not NetworkManager (which would conflict with passt's eth0 setup).
  muvmForSteam = pkgs.writeShellApplication {
    name = "muvm";
    text = ''
      exec ${lib.getExe pkgs.muvm} \
        --execute-pre ${guestDbus} \
        "$@"
    '';
  };

  steamAsahiUpstream = pkgs.steam-asahi.override {
    memoryMiB = 5 * 1024;
    muvm = muvmForSteam;
  };

  # FEX 2605's non-interactive fetcher can download an image without writing
  # Config.json. Repair that XDG state before the upstream launcher starts
  # FEXBash, otherwise FEX sees an empty RootFS despite the image being present.
  steamAsahiSession = pkgs.writeShellApplication {
    name = "steam-asahi-session";
    runtimeInputs = with pkgs; [
      coreutils
      fex
      jq
    ];
    text = ''
      if [[ -d "$HOME/.fex-emu" ]]; then
        fex_data_dir="$HOME/.fex-emu"
        fex_config="$HOME/.fex-emu/Config.json"
      else
        fex_data_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/fex-emu"
        fex_config="''${XDG_CONFIG_HOME:-$HOME/.config}/fex-emu/Config.json"
      fi

      find_rootfs() {
        local candidate
        for candidate in \
          "$fex_data_dir"/RootFS/*.ero \
          "$fex_data_dir"/RootFS/*.sqsh \
          "$fex_data_dir"/RootFS/*.img \
          "$fex_data_dir"/RootFS/*/; do
          if [[ -e "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
          fi
        done
        return 1
      }

      rootfs="$(find_rootfs || true)"
      if [[ -z "$rootfs" ]]; then
        echo "FEX rootfs not found. Downloading a Fedora rootfs..."
        echo "This is a one-time setup (about 1.3 GB)."
        FEXRootFSFetcher --assume-yes --distro-name=Fedora \
          --distro-version=43 --distro-list-first --as-is
        rootfs="$(find_rootfs || true)"
      fi

      if [[ -n "$rootfs" ]] && ! jq -e \
        '.Config.RootFS | strings | length > 0' "$fex_config" >/dev/null 2>&1; then
        mkdir -p "$(dirname "$fex_config")"
        config_tmp="$(mktemp "$(dirname "$fex_config")/.Config.json.XXXXXX")"
        jq -n --arg rootfs "$(basename "$rootfs")" \
          '{Config: {RootFS: $rootfs}}' > "$config_tmp"
        mv "$config_tmp" "$fex_config"
        echo "Configured FEX rootfs: $(basename "$rootfs")"
      fi

      exec ${lib.getExe steamAsahiUpstream} "$@"
    '';
  };

  steamAsahiService = pkgs.writeTextDir "share/systemd/user/steam-asahi-session.service" ''
    [Unit]
    Description=Steam on Apple Silicon (muvm + FEX)
    After=graphical-session.target

    [Service]
    Type=exec
    ExecStart=${lib.getExe steamAsahiSession}
    Restart=on-failure
    RestartSec=2s
    MemoryHigh=4G
    MemoryMax=6G
    MemorySwapMax=2G
    CPUQuota=200%
    CPUWeight=25
    IOWeight=25
  '';

  steamAsahiLauncher = pkgs.writeShellApplication {
    name = "steam-asahi";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      # The VM belongs to the user manager, not the launching terminal or
      # compositor client. Closing a window or terminal therefore cannot tear
      # down the whole Steam session.
      systemctl --user import-environment \
        WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS

      if ! systemctl --user cat steam-asahi-session.service >/dev/null 2>&1; then
        systemctl --user daemon-reload
      fi

      systemctl --user start steam-asahi-session.service
    '';
  };

  steamAsahi = pkgs.symlinkJoin {
    name = "steam-asahi";
    paths = [
      steamAsahiUpstream
      steamAsahiService
    ];
    postBuild = ''
      rm "$out/bin/steam-asahi"
      ln -s ${lib.getExe steamAsahiLauncher} "$out/bin/steam-asahi"
    '';
    inherit (steamAsahiUpstream) meta;
  };

  gamingDoctor = pkgs.writeShellApplication {
    name = "asahi-gaming-doctor";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      mesa-demos
      muvm
      vulkan-tools
    ];
    text = ''
      pass() {
        printf 'PASS: %s\n' "$*"
      }

      fail() {
        printf 'FAIL: %s\n' "$*" >&2
        return 1
      }

      host_checks() {
        local machine page_size
        machine="$(uname -m)"
        page_size="$(getconf PAGESIZE)"

        if [[ "$machine" == "aarch64" ]]; then
          pass "host architecture is aarch64"
        else
          fail "expected aarch64 host, found $machine"
        fi
        if [[ "$page_size" == "16384" ]]; then
          pass "host page size is 16384 bytes"
        else
          fail "expected the Apple Silicon 16384-byte host page size, found $page_size"
        fi
        if [[ -r /dev/kvm && -w /dev/kvm ]]; then
          pass "/dev/kvm is accessible"
        else
          fail "/dev/kvm is not readable and writable by $(id -un)"
        fi
        if [[ -e /dev/dri/card1 && -e /dev/dri/card2 && -e /dev/dri/renderD128 ]]; then
          pass "split Apple DRM topology is present (card1, card2, renderD128)"
        else
          fail "expected split Apple DRM nodes are missing"
        fi
        if [[ -S "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pulse/native" ]]; then
          pass "PipeWire PulseAudio socket is present"
        else
          fail "PipeWire PulseAudio socket is not present"
        fi
      }

      guest_checks() {
        # shellcheck disable=SC2016 # Expansion must happen inside the guest.
        if ${lib.getExe pkgs.muvm} --interactive -- \
          bash -c 'test "$(getconf PAGESIZE)" = 4096'; then
          pass "muvm guest page size is 4096 bytes"
        else
          fail "muvm did not provide a 4096-byte guest page size"
        fi
      }

      fex_checks() {
        # shellcheck disable=SC2016 # Expansion must happen inside FEX.
        if ${lib.getExe steamAsahi} --fex \
          'test "$(uname -m)" = x86_64'; then
          pass "FEX executes an x86-64 userspace"
        else
          fail "FEX did not execute as x86_64"
        fi
      }

      network_checks() {
        if ${lib.getExe steamAsahi} --fex \
          'test -S /run/dbus/system_bus_socket && getent ahosts api.steampowered.com >/dev/null'; then
          pass "Steam DNS and its guest system-bus signal are available"
        else
          fail "Steam DNS or the guest system-bus signal is unavailable"
        fi
      }

      gpu_checks() {
        # shellcheck disable=SC2016 # Expansion must happen inside FEX.
        if ${lib.getExe steamAsahi} --fex \
          'output="$(vulkaninfo --summary)"; printf "%s\n" "$output"; printf "%s\n" "$output" | grep -Eiq "Apple|Honeykrisp|Asahi"'; then
          pass "Apple GPU is visible through the muvm/FEX environment"
        else
          fail "translated Vulkan summary did not identify the Apple GPU"
        fi
      }

      usage() {
        cat <<'EOF'
      Usage: asahi-gaming-doctor [host|guest|fex|network|gpu|all]

        host     Verify the running host without starting a VM or downloading data.
        guest    Verify that muvm supplies a 4 KiB-page guest.
        fex      Verify x86-64 execution (may download the FEX rootfs once).
        network  Verify Steam DNS from the translated environment.
        gpu      Verify Vulkan sees the Apple GPU from that environment.
        all      Run the checks above in dependency order.
      EOF
      }

      case "''${1:-host}" in
        host) host_checks ;;
        guest) guest_checks ;;
        fex) fex_checks ;;
        network) network_checks ;;
        gpu) gpu_checks ;;
        all)
          host_checks
          guest_checks
          fex_checks
          network_checks
          gpu_checks
          ;;
        -h|--help|help) usage ;;
        *) usage >&2; exit 2 ;;
      esac
    '';
  };
in
{
  programs.steam-asahi = {
    enable = true;

    # The VM and launcher cgroup deliberately leave most of this 16 GiB host
    # available to Hyprland and interactive applications.
    memoryMiB = 5 * 1024;
    package = steamAsahi;
  };

  # muvm is rootless but requires KVM. Keep that access explicit even though
  # the currently running generation happens to expose /dev/kvm mode 0666.
  users.users.becker.extraGroups = [ "kvm" ];

  environment.systemPackages = [ gamingDoctor ];

  # Proton titles commonly create many mappings. The existing zram, swappiness,
  # and page-cluster policy remains the machine's swap strategy.
  boot.kernel.sysctl = {
    "vm.max_map_count" = 1048576;
    "vm.watermark_scale_factor" = 125;
  };

  assertions = [
    {
      assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
      message = "steam-asahi is only intended for this Apple Silicon aarch64 host";
    }
    {
      assertion = !config.programs.steam.enable;
      message = "Use programs.steam-asahi, not the incompatible native programs.steam module";
    }
    {
      assertion = !config.hardware.graphics.enable32Bit;
      message = "FEX supplies x86 32-bit support; do not enable host aarch64 32-bit graphics";
    }
  ];
}
