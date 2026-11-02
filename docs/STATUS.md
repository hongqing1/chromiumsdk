# Build status (kit mirror)

**State:** OFFICIAL_THINLTO_PUBLISHED（主 AAR：official+ThinLTO；资源 AAR：values 按名合并 + content∪ui R shim）
**Pin:** 132.0.6834.165 / crwebview 88f8fc85
**Updated:** 2026-11-01 Asia/Shanghai（GitHub Release 主 AAR 已换成 official+ThinLTO；§12.17 allowlist 已写入方案文档）

## Artifacts (GitHub Release v132.0.6834.165-arm64)

| File | Size | Notes |
|------|------|-------|
| `crwebview-132.0.6834.165.aar` | ~79.1M (82943728) | `is_official_build=true` + ThinLTO；`symbol_level=0`；`chrome_pgo_phase=0`；`enable_resource_allowlist_generation=false`（§12.17）；injected locales=83；stripped `libwebviewchromium.so` ~149.6M |
| `crwebview-res-132.0.6834.165.aar` | ~409K (417970) | content∪ui R shim（方案 §7.4）；未改 |

## Latest fix

official+ThinLTO rebuild published 2026-11-01 Asia/Shanghai. Near-end failure on `system_webview_pak_allowlist` (0 `AllowlistedResource` with ThinLTO + `symbol_level=0`) fixed by `enable_resource_allowlist_generation=false` (§12.17 / §7.2). Prior DCHECK-off ~85.3M asset replaced on the same tag.
