# Build notes — Chromium/crwebview 132.0.6834.165

实编修正已写入 [`自编译Chromium内核方案.md`](./自编译Chromium内核方案.md) 对应步骤；下表仅作索引。打补丁优先用本分支 `patches/`，不要重新踩一遍。

| 原 §12 | 方案章节 | 摘要 | kit 补丁 / 脚本 |
|--------|----------|------|-----------------|
| 12.1 | §2.2 | Profile.java import | `patches/chromium/0009-…` |
| 12.2 | §3 | `webkit_glue_java` 别名 | `0010` / layout realign |
| 12.3 | §3 | 去掉重复 `js_prompt` / `webview_find` | layout realign |
| 12.4 | §7.1 | gperf 3.2 fallthrough | `0012-color-data-fallthrough` |
| 12.5 | §2 | 磁盘监控 | — |
| 12.6–12.7 | §7.3 | `-j6` + autoninja 目标 | `scripts/` |
| 12.8 | §2.1 | PY3_PROTO 隔离 | `scripts/bin` + `python-fix` |
| 12.9 | §7.3 | 无 FAILED 静默退出 | `watch_ninja` / 续编 |
| 12.10 | §4.2 | `ScopedAllowBlockingForTesting` | `0022` |
| 12.11 | §7.4 | values 按名合并 | `packaging/merge_res_from_sources.py` |
| 12.12 | §7.4 | content∪ui R shim | `gen_r_shims.py` / `package_res_aar_finish.sh` |
| 12.13 | §4.2 | `QueryRenderMode`↔`g_use_vulkan` | `0026-allocator-query-render-mode-gles` |
