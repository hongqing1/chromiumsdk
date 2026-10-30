# Build status (kit mirror)

**State:** BOTH_AAR_DONE + §12.13 main AAR rebuild (QueryRenderMode→GLES)
**Pin:** 132.0.6834.165 / crwebview 88f8fc85
**Updated:** 2026-10-30 10:41 Asia/Shanghai

## Artifacts (GitHub Release v132.0.6834.165-arm64)

| File | Size | Notes |
|------|------|-------|
| `crwebview-132.0.6834.165.aar` | ~104.1M (109194997) | GLES QueryRenderMode fix (§12.13); assets injected |
| `crwebview-res-132.0.6834.165.aar` | ~409K (417970) | content∪ui R shim (§12.12); unchanged this rebuild |

## Latest fix

`patches/crwebview/0026-allocator-query-render-mode-gles.patch` — `QueryRenderMode` honors `g_use_vulkan` (default false → OPENGL_ES). Incremental ninja `crwebkit_aar` only; res AAR not rebuilt.
