# Build status (kit mirror)

**State:** BOTH_AAR_DONE（主 AAR：QueryRenderMode→GLES；资源 AAR：values 按名合并 + content∪ui R shim）
**Pin:** 132.0.6834.165 / crwebview 88f8fc85
**Updated:** 2026-10-30 Asia/Shanghai（方案文档：踩坑已并入步骤，§12 仅历史索引）

## Artifacts (GitHub Release v132.0.6834.165-arm64)

| File | Size | Notes |
|------|------|-------|
| `crwebview-132.0.6834.165.aar` | ~104.1M (109194997) | GLES QueryRenderMode（方案 §4.2）；assets injected |
| `crwebview-res-132.0.6834.165.aar` | ~409K (417970) | content∪ui R shim（方案 §7.4） |

## Latest fix

`patches/crwebview/0026-allocator-query-render-mode-gles.patch` — `QueryRenderMode` honors `g_use_vulkan` (default false → OPENGL_ES). Incremental ninja `crwebkit_aar` only; res AAR not rebuilt.
