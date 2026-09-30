#!/bin/bash
# Build out/vendor.img: stock T510 (32-bit) vendor + arm64 /vendor/lib64 from
# the Galaxy A30 (same Exynos 7904, same Mali r26p0 blobs).
# Halium's mount-android-partitions prefers /userdata/vendor.img (or
# /var/lib/lxc/android/vendor.img) over the vendor partition.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T510=firmware/t510/ex/img/vendor.img
A30=firmware/a305gt/ex/vendor.img
OUT=out/vendor.img
SIZE=${SIZE:-640M}
cd "$ROOT"
cp --sparse=always "$T510" "$OUT"
docker run --rm --privileged -v "$ROOT:/work" -w /work t510-build bash -ec "
e2fsck -fy $OUT >/dev/null || true
resize2fs $OUT $SIZE >/dev/null
mkdir -p /mnt/t /mnt/a
mount -o loop $OUT /mnt/t
mount -o loop,ro $A30 /mnt/a
cp -a --preserve=all /mnt/a/lib64 /mnt/t/lib64
# 64-bit executables that T510 vendor init rc files start once the system
# reports an arm64 ABI. boringssl_self_test64 is critical: when it cannot
# start, init reboots with boringssl-self-check-failed (container shutdown).
for b in boringssl_self_test64 snap_utility_64; do
  cp -a --preserve=all /mnt/a/bin/\$b /mnt/t/bin/\$b
done
ls -laZ /mnt/t/bin/boringssl_self_test* /mnt/t/bin/snap_utility*
echo \"lib64 files: \$(find /mnt/t/lib64 -type f | wc -l)\"
ls -laZ /mnt/t/lib64/egl/ 2>/dev/null || ls -la /mnt/t/lib64/egl/
df -h /mnt/t | tail -1
umount /mnt/a /mnt/t
e2fsck -fy $OUT >/dev/null || true
chown $(id -u):$(id -g) $OUT
"
ls -la "$OUT"
