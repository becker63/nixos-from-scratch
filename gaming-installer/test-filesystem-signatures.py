"""Regression: ext4 formatting alone can leave valid ZFS labels at the tail.

All operations target sparse regular files in a fresh temporary directory.
The XDR label layout matches util-linux libblkid/src/superblocks/zfs.c.
"""

import json
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def uint64_pair(name, value):
    name_bytes = name.encode() + b"\0"
    padded = name_bytes.ljust((len(name_bytes) + 3) // 4 * 4, b"\0")
    size = 12 + len(padded) + 16
    return struct.pack(">III", size, size, len(name_bytes)) + padded + struct.pack(">IIQ", 8, 1, value)


def filesystem_types(image):
    signatures = json.loads(command("wipefs", "--json", str(image)))
    return {s["type"] for s in signatures["signatures"]}


for tool in ("wipefs", "blkid", "mkfs.ext4", "mkfs.fat"):
    if shutil.which(tool) is None:
        raise SystemExit(f"Missing test dependency: {tool}")

with tempfile.TemporaryDirectory(prefix="gaming-filesystem-test-") as temporary:
    root = Path(temporary) / "root.img"
    size = 128 * 1024 * 1024
    label = bytes((1, 1, 0, 0)) + bytes(8)
    label += uint64_pair("guid", 123) + uint64_pair("state", 0) + uint64_pair("txg", 1) + bytes(8)
    with root.open("wb") as image:
        image.truncate(size)
        for base in (size - 512 * 1024, size - 256 * 1024):
            image.seek(base + 16 * 1024)
            image.write(label)
    assert filesystem_types(root) == {"zfs_member"}, "Fixture must contain detectable ZFS labels"
    # Disable discard to exercise disks that retain old data after formatting.
    command("mkfs.ext4", "-F", "-E", "nodiscard", "-L", "gaming-root", str(root))
    assert filesystem_types(root) == {"ext4", "zfs_member"}, "Old bug must be reproducible"
    command("wipefs", "--all", "--lock=yes", str(root))
    assert filesystem_types(root) == set(), "Every conflicting signature must be removed"
    command("mkfs.ext4", "-F", "-E", "nodiscard", "-L", "gaming-root", str(root))
    assert command("blkid", "-p", "-s", "TYPE", "-o", "value", str(root)).strip() == "ext4"
    assert command("blkid", "-p", "-s", "LABEL", "-o", "value", str(root)).strip() == "gaming-root"

    efi = Path(temporary) / "efi.img"
    with efi.open("wb") as image:
        image.truncate(64 * 1024 * 1024)
    command("wipefs", "--all", "--lock=yes", str(efi))
    command("mkfs.fat", "-F", "32", "-n", "GAME_EFI", str(efi))
    assert command("blkid", "-p", "-s", "TYPE", "-o", "value", str(efi)).strip() == "vfat"
    assert command("blkid", "-p", "-s", "LABEL", "-o", "value", str(efi)).strip() == "GAME_EFI"

print("PASS: reproduced lingering ZFS labels; signature cleanup restores unambiguous ext4/vfat probes")
