#!/bin/sh
# SM-T510: bind mounts inside the Android container's mount namespace
# (called from mount.sh by LXC's mount hook). Host-side binds are invisible
# in here because /system and /vendor are mounted separately.
H=/var/lib/lxc/android

# The Halium GSI's init.disabled.rc points the audio HAL services at
# *_DISABLED binaries, so no Android audio HAL runs. Re-enable them.
if [ -f "$H/init.disabled.rc.audiofix" ]; then
    mount --bind "$H/init.disabled.rc.audiofix" \
        "${LXC_ROOTFS_MOUNT}/system/etc/init/init.disabled.rc"
fi

# The Samsung HAL (audio.primary.exynos7904.so) is 32-bit only. Android's
# 64-bit audio.hidl_compat forwards to the 32-bit HIDL service instead.
if [ -f "${LXC_ROOTFS_MOUNT}/system/lib64/hw/audio.hidl_compat.default.so" ]; then
    mount --bind "${LXC_ROOTFS_MOUNT}/system/lib64/hw/audio.hidl_compat.default.so" \
        "${LXC_ROOTFS_MOUNT}/vendor/lib64/hw/audio.primary.default.so"
fi
