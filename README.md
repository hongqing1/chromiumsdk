# Chromium embed WebView AAR (arm64, Android 8+)

Self-built embeddable Chromium WebView AAR for YXT Android APK integration.

- **Pinned Chromium**: 133.0.6943.123
- **Target**: `android_webview/embed_aar:chromium_webview`
- **Out**: `out/AarArm64` (`target_os=android`, `target_cpu=arm64`)
- **Privacy**: see `docs/PRIVACY_ARGS.md` and `gn/args.gn` (reporting/telemetry disabled for CN store)

## What is in this repo

- `gn/args.gn` — effective GN args used for the AAR build
- `embed_aar/` — custom dist/package AAR GN target
- `patches/` — local patches (gperf 3.2 fallthrough, android_webview BUILD.gn)
- `scripts/watch_and_finish.sh` — poll for AAR / copy to artifacts
- `docs/` — privacy notes and pinned revision (`docs/PINNED_REV.txt`)
- `chromium_webview.aar` is a GitHub Release asset (~105MB), not committed here

## What is NOT in this repo

Full Chromium (~39G) is not in this repo. Rebuild uses depot_tools + `gclient sync` to `docs/PINNED_REV.txt` (133.0.6943.123), apply `patches/`, use `gn/args.gn`, and build the `embed_aar` target.

## Rebuild sketch

```bash
# depot_tools + gclient sync to the rev in docs/PINNED_REV.txt (133.0.6943.123)
# apply patches/
mkdir -p out/AarArm64 && cp gn/args.gn out/AarArm64/args.gn
# copy embed_aar/ into src/android_webview/embed_aar
gn gen out/AarArm64
ninja -C out/AarArm64 android_webview/embed_aar:chromium_webview
```
