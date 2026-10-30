# crwebview-132 build status

**State:** BOTH_AAR_DONE  
**Pin:** 132.0.6834.165  
**crwebview:** 88f8fc85  
**Out:** `src/out/crwebview_arm64`  
**Built:** 2026-10-29–30 Asia/Shanghai

## Summary

- Shallow Chromium checkout `132.0.6834.165` + gclient sync/runhooks
- crwebview `88f8fc85` cloned into `src/android_webview/crwebview/`; stock patches 001/002/003 (+ Profile.java import fix)
- Layout realignment (§3), Android 8 / GLES / TextureView / data-directory (§4–5), BuildConfig/log tweaks (§6)
- Local compile fixes: gperf/color_data fallthrough, java_group alias, js_prompt dedupe, PY3_PROTO wrappers, ScopedAllowBlockingForTesting
- `gn gen` OK (~63227 targets); ninja `-j6` for `crwebkit_aar` + resource targets
- Main AAR packaged with assets (icu/paks/snapshot_blob_64/83 locales); res AAR via packaging scripts with **named merge** of values XML (`merge_res_from_sources.py`)
- Res AAR **~409K** rebuilt 2026-10-30: values merge (§12.11) + **content R shim = content∪ui** so `org.chromium.content.R$array` / `ui_com_google_android_gms_fonts_certs*` exist (§12.12). Prior ~140K and styles-only ~391K obsolete
- Release: https://github.com/hongqing1/chromiumsdk/releases/tag/v132.0.6834.165-arm64
- App §9 integrate in progress (unblocked after complete res + content∪ui shim)

## Artifacts (not in git)

| File | Notes |
|------|--------|
| `crwebview-132.0.6834.165.aar` | ~105M main embed AAR (arm64) with assets |
| `crwebview-res-132.0.6834.165.aar` | **~409K** resource / R-shim AAR (merged styles + content∪ui shims / R$array) |

`v8_context_snapshot` not present in this build.

Full Chromium tree is **not** in this repo. See README.md for rebuild steps; see `docs/BUILD_PITFALLS.md` and `docs/自编译Chromium内核方案.md` §12 for pitfalls.
