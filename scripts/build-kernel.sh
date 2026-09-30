#!/bin/bash
# Build the gta3xlwifi kernel inside the t510-build container.
# Usage: scripts/build-kernel.sh [config targets...]
#   default: exynos7885-gta3xlwifi_defconfig halium.config
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGETS="${*:-exynos7885-gta3xlwifi_defconfig halium.config}"
# Audio DSP (ABOX) and amp firmware requested at ~1.4s, before any rootfs:
# built into the kernel (CONFIG_EXTRA_FIRMWARE). Proprietary, kept out of git.
FWSRC="$ROOT/firmware/t510/ex/img/vendor/firmware"
mkdir -p "$ROOT/out/extra-firmware"
for f in calliope_sram.bin calliope_dram.bin Tfa9896.cnt; do
  cp -u "$FWSRC/$f" "$ROOT/out/extra-firmware/$f"
done
docker run --rm -u "$(id -u):$(id -g)" \
  -v "$ROOT:/work" -w /work/src/android_kernel_gta3xlwifi t510-build bash -c "
set -e
export ARCH=arm64 PLATFORM_VERSION=11 ANDROID_MAJOR_VERSION=r ANDROID_VERSION=110000
export CROSS_COMPILE=/work/toolchains/gcc49/bin/aarch64-linux-android-
export KBUILD_BUILD_USER=t510 KBUILD_BUILD_HOST=ubports
O=/work/out/kernel
mkdir -p \$O
make -s O=\$O $TARGETS >/dev/null
# make 4.4 does not regenerate auto.conf for this 4.4 Makefile by itself
make -s O=\$O olddefconfig
make -s O=\$O silentoldconfig

# Report fragment options that Kconfig dropped (unmet dependencies)
for t in $TARGETS; do
  f=arch/arm64/configs/\$t
  case \$t in *_defconfig) continue;; esac
  grep -hE '^(CONFIG_[A-Z0-9_]+=|# CONFIG_[A-Z0-9_]+ is not set)' \$f | while read -r l; do
    grep -qxF \"\$l\" \$O/.config || echo \"CONFIG MISMATCH: want '\$l' got '\$(grep -E \"^(# )?\$(echo \$l | grep -oE 'CONFIG_[A-Z0-9_]+')[= ]\" \$O/.config)'\"
  done
done

make O=\$O -j\$(nproc) > \$O/build.log 2>&1 || { grep -E 'error|Error' \$O/build.log | head -40; exit 1; }
ls -la \$O/arch/arm64/boot/Image
"
