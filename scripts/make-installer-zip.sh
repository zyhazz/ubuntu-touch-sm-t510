#!/bin/bash
# Package out/halium-boot.img, out/rootfs.img and out/android-rootfs.img into
# a TWRP-flashable zip. Set T510_DEVEL=1 when rootfs.img was built with it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VARIANT=release
[ "${T510_DEVEL:-0}" = 1 ] && VARIANT=devel
VERSION=$(date -u +%Y%m%d-%H%M)
STAGE=out/.zip
for f in out/halium-boot.img out/rootfs.img out/android-rootfs.img; do
  [ -f "$f" ] || { echo "E: $f missing" >&2; exit 1; }
done
rm -rf "$STAGE"; mkdir -p "$STAGE/install"
cp -a installer/META-INF "$STAGE/"
cp installer/install/t510-install.sh "$STAGE/install/"
cp out/halium-boot.img "$STAGE/install/boot.img"
echo "I: compressing images"
docker run --rm -u "$(id -u):$(id -g)" -v "$ROOT:/work" -w /work t510-build bash -c "
  gzip -1 -c out/rootfs.img > $STAGE/install/rootfs.img.gz
  gzip -1 -c out/android-rootfs.img > $STAGE/install/android-rootfs.img.gz"
{
  echo "device=gta3xlwifi (SM-T510)"
  echo "ubuntu_touch=24.04-2.x stable"
  echo "halium=11 (GSI build 1542)"
  echo "version=$VERSION"
  echo "variant=$VARIANT"
  echo "kernel=$(git -C src/android_kernel_gta3xlwifi rev-parse --short HEAD)"
  echo "port=$(git rev-parse --short HEAD)"
  echo "rootfs_bytes=$(stat -c%s out/rootfs.img)"
  echo "android_rootfs_bytes=$(stat -c%s out/android-rootfs.img)"
} > "$STAGE/install/manifest.txt"
{
  echo "$(sha256sum < out/halium-boot.img | cut -d' ' -f1)  boot.img"
  ( cd out && sha256sum rootfs.img android-rootfs.img )
} > "$STAGE/install/SHA256SUMS"
ZIPF="out/ubuntu-touch-sm-t510-24.04-$VARIANT-$VERSION.zip"
rm -f "$ZIPF"
docker run --rm -u "$(id -u):$(id -g)" -v "$ROOT:/work" -w "/work/$STAGE" t510-build \
  zip -0 -r -q "/work/$ZIPF" META-INF install
rm -rf "$STAGE"
ls -la "$ZIPF"
