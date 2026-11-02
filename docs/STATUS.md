# Build status (kit mirror)

**State:** OFFICIAL_THINLTO_PUBLISHED（主 AAR：official+ThinLTO；资源 AAR：values 按名合并 + content∪ui R shim）
**Pin:** 132.0.6834.165 / crwebview 88f8fc85
**Updated:** 2026-11-02 Asia/Shanghai（§12.18 dat STORED；§12.19 预热已本地移除；kit tip after 2913d38（docs sync 未推），tag 仍 839e9e1）

## Artifacts (GitHub Release v132.0.6834.165-arm64)

| File | Size | Notes |
|------|------|-------|
| `crwebview-132.0.6834.165.aar` | ~79.1M (82943728) | `is_official_build=true` + ThinLTO；`symbol_level=0`；`chrome_pgo_phase=0`；`enable_resource_allowlist_generation=false`（§12.17）；injected locales=83；stripped `libwebviewchromium.so` ~149.6M |
| `crwebview-res-132.0.6834.165.aar` | ~409K (417970) | content∪ui R shim（方案 §7.4）；未改 |

## Latest

- official+ThinLTO rebuild published 2026-11-01 Asia/Shanghai. `enable_resource_allowlist_generation=false` required with `symbol_level=0`+ThinLTO (§12.17 / §7.2). Same Release tag replaced prior DCHECK-off ~85.3M main AAR.
- Kit branch `v132.0.6834.165-arm64` local tip after **2913d38** (docs sync unpushed); tag still **839e9e1** (not moved; do not claim tag advanced).
- App `origin/crwebview` tip **c8f90eac** (ThinLTO + noCompress dat restore). Local HEAD **630cd0965** removed login `about:blank` prewarm for A/B (§12.19).
- §12.18: dropping `dat` from `noCompress` → `icudtl.dat` DEFLATE → `icu_util` Invalid FD → crash (Prewarmer SIGTRAP when prewarm present). tip `6b321628` FAIL / `852bcddc` restore PASS (cold ~738 / hot ~718 vs ThinLTO `290c8219` 730/675).
- Perf (MI PAD 4, ThinLTO `290c8219`): cold mark→DrawFunctor ~730ms / hot ~675ms; FATAL=0 incl. homework.
- APK ~344MB vs commercial ~318MB era (~+25MB): not mainly so unc size; icudtl STORED ~+5.5 + other .so zip ~8–9 + dex zip ~6.5. Modest shrink without big changes exhausted on dat path (§9.1).
