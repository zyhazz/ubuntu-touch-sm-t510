#!/bin/bash
# Download and unpack the two Samsung firmwares the port is built from:
#  - SM-T510 T510XXS5CVL1 (Android 11, ZTO): flashed with Odin, and the source
#    of the 32-bit vendor, dt and audio firmware
#  - SM-A305GT A305GTVJU8CWE1 (Galaxy A30, same Exynos 7904, ZTO): donor of
#    the arm64 /vendor/lib64 and a few 64-bit vendor binaries
# Proprietary Samsung files: they stay under firmware/, never in git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x tools/samloader ] || { echo "E: run scripts/fetch-deps.sh first" >&2; exit 1; }

download() { # model region version dir
  local z
  z=$(ls "firmware/$4"/*.zip 2>/dev/null | head -1 || true)
  if [ -z "$z" ]; then
    mkdir -p "firmware/$4"
    tools/samloader download -m "$1" -r "$2" -v "$3" -d "firmware/$4"
  fi
}
download SM-T510   ZTO "T510XXS5CVL1/T510OWO5CVG2/T510XXS5CVL1/T510XXS5CVL1" t510
download SM-A305GT ZTO "A305GTVJU8CWE1/A305GTOWO8CWE1/A305GTVJU8CWE1/A305GTVJU8CWE1" a305gt

unpack() { # dir dest images...
  local dir=$1 dest=$2; shift 2
  [ -f "$dest/vendor.img" ] && return
  mkdir -p "$dest"
  ( cd "firmware/$dir" && mkdir -p ex && cd ex && unzip -o -q ../*.zip 'AP_*' 'BL_*' 'CSC_OMC_*' 2>/dev/null || unzip -o -q ../*.zip 'AP_*' )
  local ap
  ap=$(ls "firmware/$dir"/ex/AP_*.tar.md5)
  local list=""
  for i in "$@"; do list="$list $i.lz4"; done
  tar -xf "$ap" -C "$dest" $list
  docker run --rm -u "$(id -u):$(id -g)" -v "$ROOT:/work" -w "/work/$dest" t510-build bash -ec '
    for f in *.lz4; do lz4 -dqf "$f" "${f%.lz4}" && rm "$f"; done
    simg2img vendor.img vendor.raw && mv vendor.raw vendor.img
    mkdir -p vendor && debugfs -R "rdump / vendor" vendor.img 2>/dev/null || true'
}
unpack t510   firmware/t510/ex/img vendor boot dt dtbo vbmeta recovery
unpack a305gt firmware/a305gt/ex   vendor boot dt dtbo

ls -la firmware/t510/ex/*.tar.md5 firmware/t510/ex/img/vendor.img firmware/a305gt/ex/vendor.img
echo "I: Odin files are in firmware/t510/ex (BL, AP, CSC_OMC)"
