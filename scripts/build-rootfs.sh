#!/bin/bash
# Assemble out/rootfs.img (Ubuntu Touch 24.04-2.x arm64 rootfs + Halium 11 GSI
# + SM-T510 overlay + hybrid vendor.img) and out/android-rootfs.img (the GSI
# image, which the Halium initramfs expects next to rootfs.img on /data).
#
# T510_DEVEL=1 builds a debug image: SSH with password login for root and
# phablet (password $T510_DEVEL_PASSWORD, default 1234), keys/t510_ed25519.pub
# authorized for root, adb without host key verification. Never ship it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIZE=${SIZE:-6144M}
DEVEL=${T510_DEVEL:-0}
PASSWORD=${T510_DEVEL_PASSWORD:-1234}
ROOTFS_TAR=downloads/rootfs-24.04-2.x.tar.xz
GSI_TAR=downloads/halium11-gsi-1542.tar.xz
CHANNEL=24.04-2.x/arm64/android9plus/stable
cd "$ROOT"
[ -f out/vendor.img ] || { echo "E: run scripts/make-hybrid-vendor.sh first" >&2; exit 1; }

docker run --rm --privileged -v "$ROOT:/work" -w /work \
  -e SIZE="$SIZE" -e DEVEL="$DEVEL" -e PASSWORD="$PASSWORD" -e CHANNEL="$CHANNEL" \
  -e ROOTFS_TAR="$ROOTFS_TAR" -e GSI_TAR="$GSI_TAR" -e HOST_UID="$(id -u)" \
  t510-build bash -euo pipefail -c '
IMG=out/rootfs.img
STAGE=/stage
rm -f "$IMG"
truncate -s "$SIZE" "$IMG"
mkfs.ext4 -q -F -L ubuntu-touch -b 4096 "$IMG"
mkdir -p $STAGE/system
mount -o loop "$IMG" $STAGE/system
trap "umount $STAGE/system" EXIT
MNT=$STAGE/system
LXC=$MNT/var/lib/lxc/android

for t in "$ROOTFS_TAR" "$GSI_TAR"; do
  echo "I: unpacking $(basename $t)"
  tar --numeric-owner -xJf "$t" -C $STAGE
done
rm -rf $STAGE/partitions

echo "I: overlay"
cp -a --no-preserve=ownership overlay/system/. $MNT/
ln -sf /etc/systemd/system/t510-audio-hidl-compat.service \
  $MNT/etc/systemd/system/multi-user.target.wants/t510-audio-hidl-compat.service

echo "I: hybrid vendor.img -> /var/lib/lxc/android/vendor.img"
cp --sparse=always out/vendor.img $LXC/vendor.img

# The Halium initramfs uses the "halium" layout when /data/rootfs.img exists
# and then loop-mounts /data/android-rootfs.img; the installer writes it there.
cp --sparse=always $LXC/android-rootfs.img out/android-rootfs.img

echo "I: Android container overrides (the rootfs is read-only at runtime)"
# Re-enable the audio HIDL services the Halium GSI disables.
debugfs -R "cat /system/etc/init/init.disabled.rc" $LXC/android-rootfs.img 2>/dev/null | awk "
    /^service / { suppress = 0 }
    /^service vendor\.audio-hal(-2-0)? / { suppress = 1 }
    suppress { print \"# t510: audio HIDL re-enabled: \" \$0; next }
    { print }
" > $LXC/init.disabled.rc.audiofix
grep -q "t510: audio HIDL re-enabled" $LXC/init.disabled.rc.audiofix
printf "\n# SM-T510 port\n[ -x /var/lib/lxc/android/t510-mount-hooks.sh ] && . /var/lib/lxc/android/t510-mount-hooks.sh\n" >> $LXC/mount.sh

# system-image channel so the updater knows what this is (no OTA for us yet)
mkdir -p $MNT/etc/system-image/config.d
cat > $MNT/etc/system-image/channel.ini <<EOF
[service]
base: system-image.ubports.com
http_port: 80
https_port: 443
channel: $CHANNEL
device: gta3xlwifi
EOF

touch $MNT/.writable_image

# PulseAudio: the API 30 droid module calls create_audio_patch, which the
# 64-bit audio.hidl_compat bridge (HAL API 2.0) leaves unset (SIGBUS). The
# API 28 module honours the HAL version. rate=48000 matches the ABOX DSP
# (44.1 kHz gave an audible hiss). sink.fast is the low-latency output and
# underruns on long streams (noise in the browser), so default to primary.
sed -i "s#^load-module module-droid-discover .*#load-module module-droid-card-28 voice_virtual_stream=true rate=48000\\nset-default-sink sink.primary-out#" $MNT/etc/pulse/touch.pa
grep -q "module-droid-card-28" $MNT/etc/pulse/touch.pa

if [ "$DEVEL" = 1 ]; then
  echo "I: devel access (SSH password login, adb without host key check)"
  mkdir -p $MNT/etc/ssh/sshd_config.d
  # sshd keeps the first value it reads; lxc-android-config ships 50-*.conf
  # with PasswordAuthentication no, so ours must sort before it.
  printf "PasswordAuthentication yes\nPermitRootLogin yes\n" > $MNT/etc/ssh/sshd_config.d/00-t510-devel.conf
  if [ -f keys/t510_ed25519.pub ]; then
    install -d -m 700 $MNT/root/.ssh
    install -m 600 keys/t510_ed25519.pub $MNT/root/.ssh/authorized_keys
  fi
  HASH=$(openssl passwd -6 -salt t510devel "$PASSWORD")
  sed -i "s|^root:[^:]*:|root:${HASH}:|" $MNT/etc/shadow
  HASH=$(openssl passwd -6 -salt t510phab "$PASSWORD")
  sed -i "s|^phablet:[^:]*:|phablet:${HASH}:|" $MNT/etc/shadow
  grep -q "^root:.6.t510devel" $MNT/etc/shadow || { echo "E: root password not set"; exit 1; }
  ln -sf /usr/lib/systemd/system/ssh.service $MNT/etc/systemd/system/multi-user.target.wants/ssh.service
  [ -e $MNT/usr/lib/systemd/system/usb-tethering.service ] && \
    ln -sf /usr/lib/systemd/system/usb-tethering.service $MNT/etc/systemd/system/multi-user.target.wants/usb-tethering.service
  [ -f $MNT/etc/default/adbd ] && sed -i "s/^ADBD_SECURE=.*/ADBD_SECURE=0/" $MNT/etc/default/adbd
fi

sync
df -h $MNT | tail -1
umount $MNT; trap - EXIT
e2fsck -fy "$IMG" >/dev/null || true
chown $HOST_UID "$IMG" out/android-rootfs.img
'
ls -la out/rootfs.img out/android-rootfs.img
