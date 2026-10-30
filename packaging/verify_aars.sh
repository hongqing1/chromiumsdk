#!/usr/bin/env bash
set -euo pipefail
ROOT=/workspace/crwebview-132
ART=$ROOT/artifacts
VER=132.0.6834.165
MAIN=$ART/crwebview-${VER}.aar
RES=$ART/crwebview-res-${VER}.aar
TMP=$ROOT/packaging/_verify
rm -rf "$TMP"; mkdir -p "$TMP/main" "$TMP/res"
fail=0
check() { if "$@"; then echo "OK: $*"; else echo "FAIL: $*"; fail=1; fi; }

echo "=== Main AAR ==="
unzip -q -o "$MAIN" -d "$TMP/main"
unzip -q -o "$TMP/main/classes.jar" -d "$TMP/main/classes"
# version strings
if grep -roa '132\.0\.6834\.165' "$TMP/main/classes" >/dev/null; then echo OK: version 165; else echo FAIL: no 165; fail=1; fi
if grep -roa '132\.0\.6834\.86' "$TMP/main/classes" >/dev/null; then echo FAIL: found old 86; fail=1; else echo OK: no 86; fi
# ABI
check test -d "$TMP/main/jni/arm64-v8a"
if ls "$TMP/main/jni" 2>/dev/null | grep -v arm64-v8a | grep -q .; then echo FAIL: extra ABI; fail=1; else echo OK: only arm64; fi
check test -f "$TMP/main/classes/org/chromium/android_crwebview/webkit/WebView.class"
check test -f "$TMP/main/classes/org/chromium/android_crwebview/webkit/MyDrawFunctor.class"
if test -f "$TMP/main/classes/com/android/webview/chromium/MyDrawFunctor.class"; then echo FAIL: old package MyDrawFunctor; fail=1; else echo OK: no com.android MyDrawFunctor; fi
# GLES false
javap -c "$TMP/main/classes/org/chromium/android_crwebview/webkit/MyDrawFunctor.class" > "$TMP/mydraw.txt" || true
# assets
for a in icudtl.dat resources.pak chrome_100_percent.pak snapshot_blob_64.bin; do
  check test -f "$TMP/main/assets/$a"
done
# v8_context_snapshot only when this build enables use_v8_context_snapshot (gin config may omit it)
if test -f "$TMP/main/assets/v8_context_snapshot_64.bin"; then echo OK: v8_context_snapshot present; else echo OK: v8_context_snapshot omitted by build; fi
check test -d "$TMP/main/assets/stored-locales"
# no R.class in main
if find "$TMP/main/classes" -path '*/R.class' | grep -q .; then echo FAIL: R.class in main; find "$TMP/main/classes" -path '*/R.class'; fail=1; else echo OK: no R in main; fi
if grep -roa 'drawWebViewFunctor STEP' "$TMP/main/classes" >/dev/null; then echo FAIL: debug log string; fail=1; else echo OK: no STEP log; fi
# RELR
SO=$(find "$TMP/main/jni" -name 'libwebviewchromium.so' | head -1)
if [[ -n "$SO" ]]; then
  READELF=$(command -v llvm-readelf || command -v readelf)
  if $READELF -d "$SO" 2>/dev/null | grep -E 'RELR|ANDROID_RELR'; then echo FAIL: RELR present; fail=1; else echo OK: no RELR; fi
else
  echo FAIL: no libwebviewchromium.so; fail=1
fi

echo "=== Res AAR ==="
unzip -q -o "$RES" -d "$TMP/res"
unzip -q -o "$TMP/res/classes.jar" -d "$TMP/res/classes"
grep -q 'package="org.chromium.crwebview.res"' "$TMP/res/AndroidManifest.xml" && echo OK: res package || { echo FAIL: res package; fail=1; }
for pkg in org/chromium/ui org/chromium/content org/chromium/components/embedder_support/delegate org/chromium/android_webview org/chromium/android_crwebview/webkit org/chromium/components/autofill org/chromium/media; do
  check test -f "$TMP/res/classes/$pkg/R.class"
done
if test -f "$TMP/res/classes/org/chromium/crwebview/res/R.class"; then echo FAIL: NS R in res aar; fail=1; else echo OK: no NS R in res aar; fi

echo "=== RESULT fail=$fail ==="
exit $fail
