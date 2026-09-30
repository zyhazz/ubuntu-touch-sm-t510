#!/bin/bash
# Package out/halium-boot.img + out/rootfs.img into a TWRP-flashable zip.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION=$(date -u +%Y%m%d-%H%M)
STAGE=out/.zip
rm -rf "$STAGE"; mkdir -p "$STAGE/install"
cp -a installer/META-INF "$STAGE/"
cp installer/install/t510-install.sh "$STAGE/install/"
cp out/halium-boot.img "$STAGE/install/boot.img"
echo "I: compressing rootfs"
docker run --rm -u "$(id -u):$(id -g)" -v "$ROOT:/work" -w /work t510-build \
  bash -c "gzip -1 -c out/rootfs.img > $STAGE/install/rootfs.img.gz"
{
  echo "device=gta3xlwifi (SM-T510)"
  echo "ubuntu_touch=24.04-2.x stable"
  echo "halium=11 (GSI build 1542)"
  echo "version=$VERSION"
  echo "variant=devel"
  echo "kernel=$(git -C src/android_kernel_gta3xlwifi rev-parse --short HEAD)"
  echo "rootfs_bytes=$(stat -c%s out/rootfs.img)"
} > "$STAGE/install/manifest.txt"
( cp out/halium-boot.img "$STAGE/boot.img.tmp" && cd "$STAGE" && sha256sum boot.img.tmp | sed 's/boot.img.tmp/boot.img/' && rm boot.img.tmp ) > "$STAGE/install/SHA256SUMS"
( cd out && sha256sum rootfs.img ) >> "$STAGE/install/SHA256SUMS"
ZIPF="out/ubuntu-touch-t510-24.04-devel-$VERSION.zip"
rm -f "$ZIPF"
docker run --rm -u "$(id -u):$(id -g)" -v "$ROOT:/work" -w "/work/$STAGE" t510-build \
  zip -0 -r -q "/work/$ZIPF" META-INF install
rm -rf "$STAGE"
ls -la "$ZIPF"
