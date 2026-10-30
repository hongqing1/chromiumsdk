#!/usr/bin/env bash
# Build crwebview-res-132.0.6834.165.aar per plan §7 without Gradle.
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

echo "== Copy res from .res.sources =="
python3 - "$OUT" "$PKG/src/main/res" <<'PY2'
import sys
from pathlib import Path
out = Path(sys.argv[1])
dest_root = Path(sys.argv[2])
sources_list = [
    out / "gen/android_webview/crwebview_ui_android_resources.res.sources",
    out / "gen/android_webview/crwebview_content_resources.res.sources",
    out / "gen/android_webview/crwebview_embedder_support_resources.res.sources",
    out / "gen/android_webview/resources.res.sources",
    out / "gen/android_webview/crwebview/webkit_glue_resources.res.sources",
    out / "gen/components/autofill/android/autofill_java_resources.res.sources",
    out / "gen/media/base/android/media_java_resources.res.sources",
]
copied = 0
for sources in sources_list:
    if not sources.is_file():
        print("WARN: no", sources)
        continue
    for rel in sources.read_text().splitlines():
        rel = rel.strip()
        if not rel:
            continue
        srcf = (out / rel).resolve()
        if not srcf.is_file():
            print("WARN: missing", rel, "->", srcf)
            continue
        s = str(srcf)
        dest_rel = None
        for marker in ("/res_webkit/", "/res/"):
            if marker in s:
                dest_rel = s.split(marker, 1)[1]
                break
        if dest_rel is None:
            dest_rel = srcf.name
        dest = dest_root / dest_rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(srcf.read_bytes())
        copied += 1
print("copied", copied, "res files")
PY2

echo "== Generate R shims =="
python3 "$ROOT/packaging/gen_r_shims.py" "$PKG/src/main/java" \
  "org.chromium.ui=$UI_RTXT" \
  "org.chromium.content=$CONTENT_RTXT" \
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

mapfile -t FLATS < <(find "$FLAT" -type f | sort)
"$AAPT2" link --manifest "$PKG/src/main/AndroidManifest.xml" \
  --java "$LINK/java" \
  --min-sdk-version 26 --target-sdk-version 35 \
  -I "$ANDROID_JAR" \
  -o "$LINK/res.apk" \
  --auto-add-overlay \
  "${FLATS[@]}"

find "$LINK/java" -name 'R.java' | head

echo "== Compile stub NS R + shims =="
CLASSES=$ROOT/packaging/_build/classes
mkdir -p "$CLASSES"
find "$LINK/java" -name '*.java' > "$ROOT/packaging/_build/ns_r_sources.txt"
find "$PKG/src/main/java" -name '*.java' > "$ROOT/packaging/_build/shim_sources.txt"
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
