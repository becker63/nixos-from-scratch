#!/usr/bin/env bash
set -euo pipefail
iso="${1:?Usage: sudo bash flash-pny.sh /absolute/path/to/image.iso}"
[[ $EUID -eq 0 && -f "$iso" ]] || { echo 'Run as root with a built ISO file.' >&2; exit 1; }
# Bind this operation to the exact PNY device seen in this session, not /dev/sda.
mapfile -t matches < <(lsblk -dnrpo NAME,SERIAL,TRAN | awk '$2 == "AU3A092300000041" && $3 == "usb" {print $1}')
[[ ${#matches[@]} -eq 1 ]] || { echo 'The expected PNY USB is not connected uniquely.' >&2; exit 1; }
disk="${matches[0]}"
[[ $(lsblk -dnro TYPE "$disk") == disk ]] || exit 1
[[ $(stat -c %s "$iso") -le $(blockdev --getsize64 "$disk") ]] || { echo 'ISO exceeds USB capacity.' >&2; exit 1; }
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINTS "$disk"
# Refuse any mounted partition rather than guessing what to unmount.
if lsblk -nrpo MOUNTPOINTS "$disk" | grep -q '[^[:space:]]'; then
  echo 'Unmount the PNY partitions, then run this command again.' >&2; exit 1
fi
printf 'Replacing the Windows installer on PNY serial AU3A092300000041.\n'
dd if="$iso" of="$disk" bs=4M status=progress conv=fsync
# Discard cached block data so verification reads back from the USB.
blockdev --flushbufs "$disk"
bytes="$(stat -c %s "$iso")"
cmp -n "$bytes" "$iso" "$disk"
sync
printf 'Flashed and verified %s bytes.\n' "$bytes"
