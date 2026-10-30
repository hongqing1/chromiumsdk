# Chromium / crwebview 132.0.6834.165 embed WebView AAR (arm64)

Self-built embeddable Chromium WebView AARs for YXT Android (API 26+, GLES / TextureView).

| Item | Value |
|------|--------|
| Chromium pin | **132.0.6834.165** (`docs/PINNED_REV.txt`) |
| crwebview pin | **88f8fc85** (`docs/CRWEBVIEW_PIN.txt`, upstream [wuruxu/crwebview](https://github.com/wuruxu/crwebview)) |
| Out dir | `src/out/crwebview_arm64` |
| GN args | `gn/args.gn` |
| Release AARs | [v132.0.6834.165-arm64](https://github.com/hongqing1/chromiumsdk/releases/tag/v132.0.6834.165-arm64) |

**State:** BOTH_AAR_DONE (2026-10-29–30 Asia/Shanghai). Main ~104–105M + **complete res ~409K** (values XML named-merge + content∪ui R shim; see `packaging/` and 方案 §7.4). See `docs/STATUS.md`.

## What is in this branch

- `gn/args.gn` — effective GN args
- `patches/stock/` — copies of crwebview 001/002/003
- `patches/chromium/` — local Chromium-tree fixes **after** stock 001/002/003 (layout realign, gperf fallthrough, data-directory, …)
- `patches/crwebview/` — local edits on top of crwebview `88f8fc85` (Android 8 / GLES / TextureView / ScopedAllowBlockingForTesting / BuildConfig / QueryRenderMode↔g_use_vulkan)
- `scripts/` — `watch_ninja.sh`, `finish_when_aar.sh`, `supervisor.sh`, plus `bin/python3*` + `python-fix/sitecustomize.py` (PY3_PROTO isolation)
- `packaging/` — res AAR + verify scripts (no huge `_build` / `_repack` dirs)
- `docs/` — pin files, short STATUS, full 自编译方案（步骤内嵌实编修正；§12 仅历史索引）, BUILD_PITFALLS（索引）

## What is NOT in this repo

Full Chromium source / `out/` / depot_tools / ninja logs / AAR binaries. AARs are GitHub Release assets only.

## Rebuild sketch

```bash
# 0) Host: depot_tools on PATH; ~100GB+ free disk; gperf; Python 3.x
#    If Python 3.13 + system protobuf 7.x: copy scripts/bin + scripts/python-fix
#    next to your build root and put bin/ first on PATH (方案 §2.1 / docs/BUILD_PITFALLS.md).

# 1) Fetch Chromium tag 132.0.6834.165 (gclient / fetch as in docs/自编译Chromium内核方案.md §2)
cd src

# 2) Clone crwebview into android_webview/crwebview @ 88f8fc85
git clone https://github.com/wuruxu/crwebview.git android_webview/crwebview
git -C android_webview/crwebview checkout --detach 88f8fc851879853f51cc02928e95db57fe99fb0a

# 3) Stock patches 001/002/003 (from crwebview/patches or this kit’s patches/stock)
git apply --reject android_webview/crwebview/patches/001.android_webview.support_library.patch
git apply --reject android_webview/crwebview/patches/002.android_webview.glue.patch
git apply --reject android_webview/crwebview/patches/003.android_webview.BUILD.gn.patch
# If Profile.java.rej: git apply /path/to/kit/patches/chromium/0009-profile-java-import-fix.patch

# 4) Kit Chromium patches (from src/, paths assume kit checked out alongside)
KIT=../../chromiumsdk   # adjust
git apply $KIT/patches/chromium/0010-layout-realign-android_webview-BUILD.gn.patch
git apply $KIT/patches/chromium/0011-glue-webkit-glue-java-path.patch
git apply $KIT/patches/chromium/0012-color-data-fallthrough.patch
git apply $KIT/patches/chromium/0013-data-directory-suffix.patch
git apply $KIT/patches/chromium/0014-awinit-mydrawfunctor-import.patch

# 5) Kit crwebview patches (from android_webview/crwebview/)
cd android_webview/crwebview
git apply $KIT/patches/crwebview/0020-crwebview-BUILD.gn-aar-name.patch
git apply $KIT/patches/crwebview/0021-android8-textureview-webview.patch
git apply $KIT/patches/crwebview/0022-gles-scoped-allow-blocking-draw-functor.patch
git apply $KIT/patches/crwebview/0023-mydrawfunctor-gles-default.patch
git apply $KIT/patches/crwebview/0024-webview-delegate-wrapper.patch
git apply $KIT/patches/crwebview/0025-buildconfig.patch
git apply $KIT/patches/crwebview/0026-allocator-query-render-mode-gles.patch
cd ../..

# 6) GN + ninja
mkdir -p out/crwebview_arm64
cp $KIT/gn/args.gn out/crwebview_arm64/args.gn
gn gen out/crwebview_arm64
export PATH="/path/to/build-root/bin:$PATH"   # PY3 wrappers
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
export PYTHONPATH="/path/to/build-root/python-fix${PYTHONPATH:+:$PYTHONPATH}"
autoninja -C out/crwebview_arm64 -j6 \
  android_webview/crwebview:crwebkit_aar \
  android_webview/crwebview:webkit_glue_resources
  # plus resource targets listed in docs/自编译Chromium内核方案.md §7 / packaging scripts

# 7) Package res AAR + inject assets into main AAR — see packaging/ and plan §7–8
```

Patch apply order is also documented in `patches/README.md`. Procedural steps (incl. gperf / protobuf / GLES QueryRenderMode / res merge): `docs/自编译Chromium内核方案.md`. Short index: `docs/BUILD_PITFALLS.md`.

## Privacy / Safe Browsing

This 132 crwebview embed build does **not** flip Safe Browsing / privacy GN flags the way the M133 embed_aar kit did. Do not change privacy/safe browsing enablement when rebuilding from this kit unless you intentionally fork the product config.
