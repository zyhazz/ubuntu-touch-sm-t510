#!/bin/bash
# Fetch the gta3xlwifi community kernel at a pinned commit and apply this
# port's patch series (kernel/patches) on a local branch "halium-11".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
URL=https://github.com/gta3xlwifi-dev/android_kernel_gta3xlwifi
BASE=00e4b9481434f9b0b644925a9bb2feaf3940219d   # branch main, 4.4.302
DIR=src/android_kernel_gta3xlwifi

if [ ! -d "$DIR/.git" ]; then
  mkdir -p src
  git init -q "$DIR"
  git -C "$DIR" remote add origin "$URL"
fi
git -C "$DIR" fetch -q --depth 1 origin "$BASE"
git -C "$DIR" checkout -q -B halium-11 "$BASE"

# The upstream tree tracks build output (.config, include/config, generated
# asm headers, host tool binaries). They shadow O= builds via VPATH.
git -C "$DIR" rm -q -r --ignore-unmatch --pathspec-from-file="$ROOT/kernel/remove-generated.txt"
git -C "$DIR" -c user.name=t510-port -c user.email=t510-port@localhost \
  commit -q -m "Remove generated build artifacts from tree"

git -C "$DIR" -c user.name=t510-port -c user.email=t510-port@localhost \
  am -q "$ROOT"/kernel/patches/*.patch
git -C "$DIR" log --oneline -3
