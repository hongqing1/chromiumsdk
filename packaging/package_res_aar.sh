#!/usr/bin/env bash
# Package crwebview-res-132.0.6834.165.aar from ninja gen/ outputs.
set -euo pipefail
ROOT=/workspace/crwebview-132
OUT="$ROOT/src/out/crwebview_arm64"
PKGDIR="$ROOT/packaging/crwebview-res"
VER=132.0.6834.165
AAR_OUT="$ROOT/artifacts/crwebview-res-${VER}.aar"
rm -rf "$PKGDIR"
mkdir -p "$PKGDIR/src/main/res" "$PKGDIR/src/main/java"

# Locate R.txt files for the seven packages (best-effort discover)
echo "Discovering R.txt under gen/ ..."
find "$OUT/gen" -name 'R.txt' 2>/dev/null | tee "$ROOT/packaging/r_txt_list.txt" | head -80

echo "Script expects caller to map packages after discovery; see package_res_aar_finish.sh"
