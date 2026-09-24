# Steam/Proton on Apple Silicon

This host uses the following compatibility path:

```text
x86-64 Windows game -> Proton -> FEX -> 4 KiB muvm guest -> Asahi Mesa -> Apple GPU
```

The host remains a 16 KiB-page `aarch64-linux` NixOS system. The gaming module
does not replace the Asahi kernel, Mesa, GDM, Wayland, Hyprland, or the existing
split-GPU preflight. It also deliberately leaves native `programs.steam` and
host `hardware.graphics.enable32Bit` disabled; the x86 and x86-32 userspaces
come from FEX's root filesystem.

## Declarative pieces

- `steam-asahi` is pinned as a flake input. Nixpkgs still provides muvm, FEX,
  libkrun, libkrunfw, virglrenderer, Mesa, and Steam itself.
- `programs.steam-asahi` supplies the NixOS/FEX/PressureVessel launcher glue
  that is not yet in Nixpkgs.
- The `becker` user has explicit `kvm` group membership.
- The microVM is capped at 5 GiB. Its launcher starts a detached systemd user
  service with a 4 GiB memory-high threshold, 6 GiB hard memory limit
  (including VM overhead), two-core CPU quota, and low CPU/I/O weights.
  Direct launches from Tofi and a terminal therefore preserve resources for
  Hyprland and other interactive applications. The service restarts after an
  unexpected close signal, while a clean Steam exit remains respected.
- A bare system D-Bus is started inside the guest before Steam. Steam uses it
  as a network-state signal even though passt provides the actual network;
  NetworkManager itself is intentionally not started in the guest.
- The existing 50%-of-RAM zram policy remains in place. Gaming adds only the
  commonly needed map-count and memory-watermark sysctls.

The FEX root filesystem, Steam self-updates, shader caches, Proton prefixes,
and game libraries are runtime user data. On the first FEX check,
`steam-asahi` downloads a roughly 1.3 GB Fedora root filesystem to the user's
XDG data directory.

## Staged verification

Do not skip directly to a game. Run each stage and stop at the first failure:

```bash
# 1. Host architecture, 16 KiB pages, KVM, DRM nodes, and PipeWire socket
asahi-gaming-doctor host

# 2. The 4 KiB-page microVM; this does not require a FEX rootfs
asahi-gaming-doctor guest

# 3. x86-64 execution; first use may download the FEX rootfs
asahi-gaming-doctor fex

# 4. DNS/networking through the same muvm + FEX path Steam uses
asahi-gaming-doctor network

# 5. Vulkan and Apple-GPU visibility through that environment
asahi-gaming-doctor gpu
```

`asahi-gaming-doctor all` runs the same sequence. The expected decisive values
are a 16384-byte host page size, a 4096-byte guest page size, `x86_64` from the
FEX stage, and an Apple/Asahi/Honeykrisp renderer in the Vulkan summary.

## Steam and Proton

After every diagnostic stage passes, start Steam with:

```bash
steam-asahi
```

Steam authentication and Steam Guard are manual. No credential belongs in
this repository or in a command-line argument. Stop at the login UI if the
account is not already authenticated.

Once logged in:

1. Let Steam finish its own client update.
2. Open **Settings -> Compatibility** and enable Steam Play for supported
   titles and for all other titles.
3. Select Proton Experimental first. Change Proton versions only when a title
   has a known compatibility reason.
4. Install a small game already owned by the account. Prefer STRAFTAT if it is
   present in the library.
5. Launch once with no game-specific compatibility flags. If diagnosis is
   needed, use `PROTON_LOG=1 %command%` in that game's launch options; the log
   appears as `~/steam-APPID.log`.

A successful native-looking window is not enough evidence by itself. For a
full-stack pass, confirm that the game uses Proton, creates a `compatdata`
prefix, initializes DXVK/Vulkan in its Proton log, renders through the Apple
GPU rather than llvmpipe, has working audio, and reaches an online/networked
screen when the game provides one.

## Build-time check

This targeted check evaluates the NixOS integration and builds the launcher,
FEX, muvm, and diagnostic wrapper without building or activating a NixOS
system closure:

```bash
nix build .#checks.aarch64-linux.asahi-gaming --no-link
```

It asserts that `linux-asahi`, Asahi graphics, zram, and the incompatible
native Steam/32-bit host options keep their intended values.

If the repository's next NixOS generation points at a different Asahi kernel,
the userspace packages can be activated temporarily without building or
selecting that generation:

```bash
nix profile add .#steam-asahi .#asahi-gaming-doctor
```

This profile installation is only a bridge; the repository module remains the
source of truth and should take over after the kernel transition is separately
validated.
