#!/usr/bin/env bash
# Build crwebview-res-132.0.6834.165.aar per plan §7 without Gradle.
# Merges values/*.xml across the 7 resource targets (no last-write-wins),
# plus shared_with_webview dimens and grit string zips needed by layouts.
set -euo pipefail
ROOT=/workspace/crwebview-132
OUT="$ROOT/src/out/crwebview_arm64"
PKG="$ROOT/packaging/crwebview-res"
VER=132.0.6834.165
ART="$ROOT/artifacts"
AAR_OUT="$ART/crwebview-res-${VER}.aar"
BT="$ROOT/src/third_party/android_sdk/public/build-tools/35.0.0"
ANDROID_JAR="$ROOT/src/third_party/android_sdk/public/platforms/android-35/android.jar"
AAPT2="$BT/aapt2"

rm -rf "$PKG" "$ROOT/packaging/_build"
mkdir -p "$PKG/src/main/res" "$PKG/src/main/java" "$ART" "$ROOT/packaging/_build"

GEN="$OUT/gen"
UI_RTXT="$GEN/android_webview/crwebview_ui_android_resources_R.txt"
[[ -f "$UI_RTXT" ]] || UI_RTXT="$GEN/ui/android/ui_java_resources_R.txt"
CONTENT_RTXT="$GEN/android_webview/crwebview_content_resources_R.txt"
[[ -f "$CONTENT_RTXT" ]] || CONTENT_RTXT="$GEN/content/public/android/content_java_resources_R.txt"
EMBED_RTXT="$GEN/android_webview/crwebview_embedder_support_resources_R.txt"
[[ -f "$EMBED_RTXT" ]] || EMBED_RTXT="$GEN/components/embedder_support/android/web_contents_delegate_java_resources_R.txt"
AW_RTXT="$GEN/android_webview/resources_R.txt"
WEBKIT_RTXT="$GEN/android_webview/crwebview/webkit_glue_resources_R.txt"
AUTOFILL_RTXT="$GEN/components/autofill/android/autofill_java_resources_R.txt"
MEDIA_RTXT="$GEN/media/base/android/media_java_resources_R.txt"

{
  echo "UI=$UI_RTXT"
  echo "CONTENT=$CONTENT_RTXT"
  echo "EMBED=$EMBED_RTXT"
  echo "AW=$AW_RTXT"
  echo "WEBKIT=$WEBKIT_RTXT"
  echo "AUTOFILL=$AUTOFILL_RTXT"
  echo "MEDIA=$MEDIA_RTXT"
} | tee "$ROOT/packaging/r_txt_list.txt"

missing=0
for v in UI_RTXT CONTENT_RTXT EMBED_RTXT AW_RTXT WEBKIT_RTXT AUTOFILL_RTXT MEDIA_RTXT; do
  [[ -n "${!v}" && -f "${!v}" ]] || { echo "MISSING $v"; missing=1; }
done
[[ $missing -eq 0 ]] || { echo "Cannot map all R.txt"; exit 1; }

echo "== Merge res from .res.sources (+ shared_with_webview + grit strings) =="
python3 "$ROOT/packaging/merge_res_from_sources.py" "$OUT" "$PKG/src/main/res"

echo "== Generate R shims =="
# content_java merges transitive ui resources into content.R (Chromium-faithful).
# Without ui∪content, AndroidFontLookupImpl crashes: NoClassDefFoundError content/R$array
# for R.array.ui_com_google_android_gms_fonts_certs.
echo "content shim sources: CONTENT ∪ UI"
python3 "$ROOT/packaging/gen_r_shims.py" "$PKG/src/main/java" \
  "org.chromium.ui=$UI_RTXT" \
  "org.chromium.content=${CONTENT_RTXT}+${UI_RTXT}" \
  "org.chromium.components.embedder_support.delegate=$EMBED_RTXT" \
  "org.chromium.android_webview=$AW_RTXT" \
  "org.chromium.android_crwebview.webkit=$WEBKIT_RTXT" \
  "org.chromium.components.autofill=$AUTOFILL_RTXT" \
  "org.chromium.media=$MEDIA_RTXT"

echo "== AndroidManifest =="
cat > "$PKG/src/main/AndroidManifest.xml" <<MAN
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="org.chromium.crwebview.res">
    <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/>
</manifest>
MAN

echo "== aapt2 compile + link =="
FLAT=$ROOT/packaging/_build/flat
LINK=$ROOT/packaging/_build/link
mkdir -p "$FLAT" "$LINK"
find "$PKG/src/main/res" -type f | sort > "$ROOT/packaging/_build/res_files.txt"
if [[ ! -s "$ROOT/packaging/_build/res_files.txt" ]]; then
  echo "ERROR: no res files copied"; exit 1
fi
echo "res file count: $(wc -l < "$ROOT/packaging/_build/res_files.txt")"
while IFS= read -r f; do
  "$AAPT2" compile -o "$FLAT/" "$f" || { echo "aapt2 compile failed: $f"; exit 1; }
done < "$ROOT/packaging/_build/res_files.txt"

STUB_DIR=$ROOT/packaging/_build/stub_res/values
mkdir -p "$STUB_DIR"
STUB_XML=$STUB_DIR/appcompat_stub.xml
cat > "$STUB_XML" <<STUB
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <style name="Theme.AppCompat.DayNight" parent="@android:style/Theme.DeviceDefault"/>
</resources>
STUB
"$AAPT2" compile -o "$FLAT/" "$STUB_XML"

mapfile -t FLATS < <(find "$FLAT" -type f | sort)
LINK_OK=0
if "$AAPT2" link --manifest "$PKG/src/main/AndroidManifest.xml" \
  --java "$LINK/java" \
  --min-sdk-version 26 --target-sdk-version 35 \
  -I "$ANDROID_JAR" \
  -o "$LINK/res.apk" \
  --auto-add-overlay \
  "${FLATS[@]}"; then
  LINK_OK=1
  echo "aapt2 link OK"
else
  echo "WARN: aapt2 link failed; generating synthetic NS R.java from R.txt union"
fi

NS_JAVA_DIR=$ROOT/packaging/_build/ns_java/org/chromium/crwebview/res
mkdir -p "$NS_JAVA_DIR"
if [[ $LINK_OK -eq 1 ]]; then
  find "$LINK/java" -name "R.java" -exec cp {} "$NS_JAVA_DIR/R.java" \;
else
  python3 - "$NS_JAVA_DIR/R.java" \
    "$UI_RTXT" "$CONTENT_RTXT" "$EMBED_RTXT" "$AW_RTXT" "$WEBKIT_RTXT" "$AUTOFILL_RTXT" "$MEDIA_RTXT" <<PY
import sys
from collections import defaultdict
out = sys.argv[1]
types = defaultdict(set)
for path in sys.argv[2:]:
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 3:
                types[parts[1]].add((parts[0], parts[2]))
lines = ["package org.chromium.crwebview.res;", "", "public final class R {"]
for rtype in sorted(types):
    lines.append(f"    public static final class {rtype} {{")
    for kind, name in sorted(types[rtype], key=lambda x: x[1]):
        if kind == "int[]":
            lines.append(f"        public static int[] {name} = new int[]{{0x7f010001}};")
        else:
            lines.append(f"        public static {kind} {name} = 0x7f010001;")
    lines.append("    }")
lines.append("}")
open(out, "w").write("\n".join(lines) + "\n")
print("wrote synthetic", out, "types", len(types), "fields", sum(len(v) for v in types.values()))
PY
fi

python3 - "$NS_JAVA_DIR/R.java" <<PY
import re, sys
p = sys.argv[1]
t = open(p).read()
nt = re.sub(r"public static final (int|\\[I\\]) ", r"public static \\1 ", t)
nt = re.sub(r"public static final int\\[\\] ", "public static int[] ", nt)
if nt != t:
    open(p, "w").write(nt)
    print("rewrote NS R.java to non-final fields")
else:
    print("NS R.java already non-final or synthetic")
PY

echo "== Compile stub NS R + shims =="
CLASSES=$ROOT/packaging/_build/classes
mkdir -p "$CLASSES"
find "$ROOT/packaging/_build/ns_java" -name "*.java" > "$ROOT/packaging/_build/ns_r_sources.txt"
find "$PKG/src/main/java" -name "*.java" > "$ROOT/packaging/_build/shim_sources.txt"
javac --release 17 -cp "$ANDROID_JAR" -d "$CLASSES" @"$ROOT/packaging/_build/ns_r_sources.txt"
javac --release 17 -cp "$ANDROID_JAR:$CLASSES" -d "$CLASSES" @"$ROOT/packaging/_build/shim_sources.txt"

echo "== classes.jar without org.chromium.crwebview.res.R =="
JARDIR=$ROOT/packaging/_build/jardir
rm -rf "$JARDIR"
mkdir -p "$JARDIR"
cp -a "$CLASSES/." "$JARDIR/"
rm -rf "$JARDIR/org/chromium/crwebview/res"
(cd "$JARDIR" && jar cf "$ROOT/packaging/_build/classes.jar" .)

echo "== Assemble AAR =="
AARDIR=$ROOT/packaging/_build/aardir
rm -rf "$AARDIR"
mkdir -p "$AARDIR/res"
cp "$PKG/src/main/AndroidManifest.xml" "$AARDIR/"
cp "$ROOT/packaging/_build/classes.jar" "$AARDIR/"
cp -a "$PKG/src/main/res/." "$AARDIR/res/"
cat "$UI_RTXT" "$CONTENT_RTXT" "$EMBED_RTXT" "$AW_RTXT" "$WEBKIT_RTXT" "$AUTOFILL_RTXT" "$MEDIA_RTXT" \
  | sort -u > "$AARDIR/R.txt" || true
rm -f "$AAR_OUT"
(cd "$AARDIR" && zip -qr "$AAR_OUT" .)
ls -lh "$AAR_OUT"
echo "PACKAGED $AAR_OUT"
