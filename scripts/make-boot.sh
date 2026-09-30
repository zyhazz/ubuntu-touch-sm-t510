#!/bin/bash
# Pack out/kernel Image + Halium initramfs into a boot.img with the stock
# T510XXS5CVL1 header layout (v1, 2K pages, base 0, kernel @0x10008000).
# Usage: scripts/make-boot.sh [ramdisk] [output]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAMDISK="${1:-downloads/initrd.img-touch-arm64}"
OUT="${2:-out/halium-boot.img}"
cd "$ROOT"
docker run --rm -u "$(id -u):$(id -g)" -v "$ROOT:/work" -w /work t510-build \
  python3 tools/mkbootimg/mkbootimg.py --header_version 1 --os_version 11.0.0 --os_patch_level 2022-12 \
    --kernel out/kernel/arch/arm64/boot/Image --ramdisk "$RAMDISK" \
    --pagesize 2048 --base 0x00000000 --kernel_offset 0x10008000 \
    --ramdisk_offset 0x00000000 --second_offset 0x00000000 \
    --tags_offset 0x10000100 --board SRPSA25A005KU \
    --cmdline "androidboot.selinux=permissive" \
    --output "$OUT"
ls -la "$OUT"
