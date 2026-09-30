# Ubuntu Touch 24.04 no Samsung Galaxy Tab A 10.1 (2019), SM-T510

Port experimental baseado no método do Galaxy A50
(github.com/sadatdaniel/a50-ubuntu-touch): kernel standalone + Halium 11 GSI.

Diferença principal: o vendor stock do T510 é 32 bits (arm + binder64), o
kernel já é arm64. O rootfs traz um `vendor.img` híbrido (vendor do T510 +
`/vendor/lib64` do Galaxy A30 SM-A305GT, mesmo Exynos 7904 e mesmo Mali
r26p0) em `/var/lib/lxc/android/vendor.img`, que o `mount-android-partitions`
prefere à partição vendor.

## Build (WSL2/Linux + Docker)
    docker build -t t510-build docker/
    scripts/build-kernel.sh          # src/android_kernel_gta3xlwifi, branch halium-11
    scripts/make-boot.sh             # out/halium-boot.img
    scripts/make-hybrid-vendor.sh    # out/vendor.img
    scripts/build-rootfs.sh          # out/rootfs.img (UT 24.04-2.x + GSI 1542)
    scripts/make-installer-zip.sh    # zip para o TWRP

Kernel: github.com/gta3xlwifi-dev/android_kernel_gta3xlwifi (main, 4.4.302) +
commits locais em `halium-11`. Toolchain: AOSP GCC 4.9 (android-9.0.0_r61).
