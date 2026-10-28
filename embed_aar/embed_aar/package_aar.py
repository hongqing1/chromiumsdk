#!/usr/bin/env python3
"""Merge a Java-only Chromium dist_aar with libwebviewchromium.so into final AAR."""
import argparse
import os
import shutil
import tempfile
import zipfile


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--java-aar", required=True)
    ap.add_argument("--native-lib", required=True)
    ap.add_argument("--abi", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        with zipfile.ZipFile(args.java_aar, "r") as zf:
            zf.extractall(td)
        jni_dir = os.path.join(td, "jni", args.abi)
        os.makedirs(jni_dir, exist_ok=True)
        dest_so = os.path.join(jni_dir, os.path.basename(args.native_lib))
        shutil.copy2(args.native_lib, dest_so)
        # Ensure empty R.txt / proguard if missing
        for name in ("R.txt", "proguard.txt"):
            path = os.path.join(td, name)
            if not os.path.exists(path):
                open(path, "a").close()
        if os.path.exists(args.output):
            os.remove(args.output)
        with zipfile.ZipFile(args.output, "w", compression=zipfile.ZIP_DEFLATED) as out:
            for root, _dirs, files in os.walk(td):
                for f in files:
                    full = os.path.join(root, f)
                    rel = os.path.relpath(full, td)
                    out.write(full, rel)
        print("Wrote", args.output, "size", os.path.getsize(args.output))


if __name__ == "__main__":
    main()
