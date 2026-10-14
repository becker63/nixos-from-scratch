# Rendered by writeShellApplication. Run only from the x86 UEFI installer.
if [[ "${1:-}" == --list ]]; then
  lsblk -d -o PATH,SIZE,MODEL,SERIAL,TRAN,RM
  exit 0
fi
[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
[[ $(uname -m) == x86_64 && -d /sys/firmware/efi ]] || {
  echo 'Boot this installer on the x86 gaming PC in UEFI mode.' >&2; exit 1;
}
[[ -e /dev/disk/by-label/NIXOS_GAMING_INSTALL ]] || { echo 'Installer media not found.' >&2; exit 1; }
if mountpoint -q /mnt; then echo '/mnt is already mounted; refusing to overwrite it.' >&2; exit 1; fi
@NETWORKCHECK@
lsblk -d -o PATH,SIZE,MODEL,SERIAL,TRAN,RM
printf '\nChoose the internal disk to ERASE (for example /dev/nvme0n1): '
read -r selected
disk="$(readlink -f -- "$selected")"
[[ -b "$disk" && $(lsblk -dnro TYPE "$disk") == disk ]] || { echo 'Not a whole disk.' >&2; exit 1; }
[[ $(lsblk -dnro TRAN "$disk") != usb && $(lsblk -dnro RM "$disk") == 0 ]] || {
  echo 'Refusing USB/removable disks.' >&2; exit 1;
}
media="$(readlink -f /dev/disk/by-label/NIXOS_GAMING_INSTALL)"
if lsblk -nrpo NAME "$disk" | grep -Fxq "$media"; then
  echo 'Refusing the installer disk.' >&2; exit 1
fi
if lsblk -nrpo MOUNTPOINTS "$disk" | grep -q '[^[:space:]]'; then
  echo 'Target has mounted filesystems. Unmount them first.' >&2; exit 1
fi
[[ $(lsblk -bdnro SIZE "$disk") -ge 68719476736 ]] || { echo 'A disk of at least 64 GiB is required.' >&2; exit 1; }
lsblk -d -o PATH,SIZE,MODEL,SERIAL "$disk"
printf 'Type ERASE %s to confirm: ' "$disk"
read -r confirmation
[[ "$confirmation" == "ERASE $disk" ]] || { echo 'Cancelled.'; exit 1; }
printf 'Set the becker login/sudo password: '
read -rs password
printf '\nRepeat password: '
read -rs repeated
printf '\n'
[[ -n "$password" && "$password" == "$repeated" ]] || { echo 'Passwords did not match or were empty.' >&2; exit 1; }
password_hash="$(printf '%s' "$password" | openssl passwd -6 -stdin)"
unset password repeated

# GPT creation and mkfs do not reliably remove signatures from previous formats
# (notably ZFS labels near the end of a device). Erasure is already confirmed.
wipefs --all --lock=yes "$disk"
parted -s "$disk" -- mklabel gpt mkpart ESP fat32 1MiB 1025MiB set 1 esp on mkpart root ext4 1025MiB 100%
partprobe "$disk"
udevadm settle
mapfile -t partitions < <(lsblk -nrpo NAME,TYPE "$disk" | awk '$2 == "part" {print $1}')
[[ ${#partitions[@]} -eq 2 ]] || { echo 'Unexpected partition layout.' >&2; exit 1; }
wipefs --all --lock=yes "${partitions[0]}" "${partitions[1]}"
mkfs.fat -F 32 -n GAME_EFI "${partitions[0]}"
mkfs.ext4 -F -L gaming-root "${partitions[1]}"
for partition in "${partitions[@]}"; do
  udevadm trigger --action=change --subsystem-match=block --sysname-match="$(basename "$partition")"
done
udevadm settle
[[ $(blkid -p -s TYPE -o value "${partitions[0]}") == vfat ]] || { echo 'EFI filesystem probe did not find vfat.' >&2; exit 1; }
[[ $(blkid -p -s TYPE -o value "${partitions[1]}") == ext4 ]] || { echo 'Root filesystem probe did not find ext4.' >&2; exit 1; }
mount -t ext4 "${partitions[1]}" /mnt
trap 'umount -R /mnt || true' EXIT
mkdir -p /mnt/boot
mount -t vfat "${partitions[0]}" /mnt/boot
mkdir -p /mnt/etc/nixos
cp -r @SOURCE@/. /mnt/etc/nixos/
chmod -R u+w /mnt/etc/nixos
cp -r @DESKTOP@ /mnt/etc/nixos/config
cp @WALLPAPER@ /mnt/etc/nixos/wallpaper.jpg
# These files are tracked templates; their installed paths are self-contained.
cp /mnt/etc/nixos/installed-configuration.nix /mnt/etc/nixos/configuration.nix
sed 's|NIXPKGS_SOURCE_PATH|@NIXPKGS@|g' /mnt/etc/nixos/installed-system.nix > /mnt/etc/nixos/system.nix
# This is the locally bundled, pinned source, not a signed binary-cache output.
# Limit the signature exception to this one local transfer into the target store.
nix --extra-experimental-features nix-command copy --no-check-sigs --to /mnt @NIXPKGS@
@INSTALL@
# mutableUsers keeps this hash across later configuration rebuilds.
printf 'becker:%s\n' "$password_hash" | nixos-enter --root /mnt -c 'chpasswd -e'
unset password_hash
sync
printf '\nInstalled. Remove the USB after shutdown, then boot gaming-box.\n'
printf 'Steam Switch to Desktop -> Hyprland; Alt+Shift+G -> gaming; Ctrl+Alt+F2 -> login terminal.\n'
