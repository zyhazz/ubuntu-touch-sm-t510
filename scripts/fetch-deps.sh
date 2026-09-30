#!/bin/bash
# Download everything the build needs that is not in this repository:
# toolchain, mkbootimg, samloader-rs, the Halium initramfs, the Ubuntu Touch
# rootfs, the pinned Halium 11 GSI and the TWRP build for gta3xlwifi.
# Idempotent: skips files that are already present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p downloads toolchains tools firmware/twrp

fetch() { # url dest [sha256]
  [ -s "$2" ] || { echo "I: fetching $(basename "$2")"; curl -fL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; }
  if [ -n "${3:-}" ]; then
    echo "$3  $2" | sha256sum -c --quiet - || { echo "E: checksum mismatch for $2" >&2; exit 1; }
  fi
}

# AOSP GCC 4.9 (Samsung builds this kernel with it). The android-11 tags
# dropped the compiler; android-9.0.0_r61 still has it.
if [ ! -x toolchains/gcc49/bin/aarch64-linux-android-gcc-4.9.x ]; then
  mkdir -p toolchains/gcc49
  curl -fsSL "https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-9.0.0_r61.tar.gz" \
    | tar xz -C toolchains/gcc49
  # bin/aarch64-linux-android-gcc is a python2 wrapper; call the compiler directly
  mv toolchains/gcc49/bin/aarch64-linux-android-gcc toolchains/gcc49/bin/aarch64-linux-android-gcc.wrapper
  ln -s aarch64-linux-android-gcc-4.9.x toolchains/gcc49/bin/aarch64-linux-android-gcc
fi

# Ubuntu's mkbootimg package is broken (missing gki module); use LineageOS'.
[ -d tools/mkbootimg ] || git clone -q --depth 1 -b lineage-20.0 \
  https://github.com/LineageOS/android_system_tools_mkbootimg tools/mkbootimg

# samloader-rs downloads Samsung firmware without an IMEI/serial.
if [ ! -x tools/samloader ]; then
  fetch https://github.com/topjohnwu/samloader-rs/releases/download/2.2.0/samloader-v2.2.0-linux-x86_64.zip \
    tools/samloader.zip
  python3 -m zipfile -e tools/samloader.zip tools/ && chmod +x tools/samloader && rm tools/samloader.zip
fi

fetch https://github.com/halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-arm64 \
  downloads/initrd.img-touch-arm64

# Ubuntu Touch 24.04-2.x stable rootfs (published for FP5, generic arm64).
fetch https://system-image.ubports.com/pool/rootfs-7a39ccd6d9f9e501f42a7d0a443df2c766cbb9f32428555e167ce4d1a542be2b.tar.xz \
  downloads/rootfs-24.04-2.x.tar.xz

# Halium 11 generic arm64 GSI, pinned (same build the A50 port ships).
fetch "https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64/job/halium-11.0/1542/artifact/halium_halium_arm64.tar.xz" \
  downloads/halium11-gsi-1542.tar.xz 48ed0fd15c3b6b3a29de2b683c511ab9fb54f148b6e25556dbe6a1767fb6d2a3

# Magendanz TWRP 3.7.0 for the SM-T510 (Android 11 bootloader)
fetch https://github.com/gta3xlwifi-dev/android_device_samsung_gta3xlwifi_twrp/releases/download/v3.7.0_11-0-T510XXU5CWA1/twrp-3.7.0_11-0-T510XXU5CWA1-20230330.tar.md5 \
  firmware/twrp/twrp-3.7.0_11-0-T510XXU5CWA1-20230330.tar.md5

echo "I: done. Next: scripts/extract-firmware.sh"
