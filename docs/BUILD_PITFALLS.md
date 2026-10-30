# Build pitfalls — Chromium/crwebview 132.0.6834.165

Extracted from `自编译Chromium内核方案.md` §12 (实编踩坑). Apply the corresponding patches under `patches/` rather than re-discovering these.

## 12. 编译踩坑（132.0.6834.165 实编）

这一节记的是按上文编 `crwebkit_aar` 时实际碰到的问题和改法。补丁与第 3～6 节里的产品改动分开，方便下次原样重编。

### 12.1 `002` 在 Profile.java 上留下 .rej

| 项 | 内容 |
|----|------|
| 现象 | `git apply --reject` 后 `glue/.../Profile.java.rej`，其它文件可打上 |
| 原因 | `132.0.6834.165` 在 `NonNull` 前多了一个 `AnyThread` import，补丁上下文对不上 |
| 改法 | 见第 2 节：把五个 `android.webkit.*` import 换成 `org.chromium.android_crwebview.webkit.*`，删掉 `.rej` |

### 12.2 布局对齐后仍有目标指向旧 `webkit_glue_java`

| 项 | 内容 |
|----|------|
| 现象 | `gn gen` 或依赖解析报找不到 `//android_webview:webkit_glue_java`（support_library 等仍写旧路径） |
| 原因 | 第 3 节把 `webkit_glue_java` 挪到 `//android_webview/crwebview:`，旧 label 还在 |
| 改法 | 在 `android_webview/BUILD.gn` 加别名，不要把源再拷回旧位置： |

```gn
# Alias: webkit_glue_java lives in crwebview/ after layout realignment (§3).
java_group("webkit_glue_java") {
  deps = [ "//android_webview/crwebview:webkit_glue_java" ]
}
```

### 12.3 `js_prompt` / `webview_find` 资源重复

| 项 | 内容 |
|----|------|
| 现象 | 编资源阶段失败，或同名 layout 进了两份 resources |
| 原因 | 第 3 节布局后，`js_prompt.xml`、`webview_find` 已在 `//android_webview/crwebview:webkit_glue_resources`；`android_webview/BUILD.gn` 的 `android_resources("resources")` 若仍列出同路径会重复 |
| 改法 | 从 `android_webview:resources` 的 `sources` 里删掉这两项，只保留 crwebview 侧；注释标明归属 |

### 12.4 gperf 3.2 + clang：`color_data.cc` fallthrough（编到约一半会挂）

| 项 | 内容 |
|----|------|
| 现象 | `CXX .../color_data.o` 报大量 `error: fallthrough annotation does not directly precede switch label`；ninja 退出。盲目重启会在同一处反复失败 |
| 原因 | 编译机若是 **gperf 3.2.x**（本次 `gperf --version` → 3.2.1），生成的 `color_data.cc` 里带 `#if … [[fallthrough]]; #elif … #endif`，`#endif` 夹在注解和下一个 `case` 之间，clang 的 `-Wimplicit-fallthrough` 不认。Chromium 自带的 `gperf.py` 还会把 `/*FALLTHROUGH*/` 再写成 `[[fallthrough]];`，和 3.2 的块叠在一起 |
| 改法（三处一起做，再生也稳） | 见下 |

1. `third_party/blink/renderer/platform/color_data.gperf` 头里（已有 shorten-64 的 pragma 旁）加上：

```c
#pragma clang diagnostic ignored "-Wimplicit-fallthrough"
#pragma GCC diagnostic ignored "-Wimplicit-fallthrough"
```

2. `third_party/blink/renderer/build/scripts/gperf.py`：在把 `/*FALLTHROUGH*/` 换成 `[[fallthrough]];` **之前**，先删掉 gperf 3.2 插入的整段 `#if / [[fallthrough]] / #elif / __attribute__ / #endif`，只留脚本写在 `case` 正上方的那一条注解。

3. 若 `out/.../gen/.../color_data.cc` 已经生成坏了：按同样规则改生成文件，或删掉该 gen 文件让 ninja 重跑 `color_data` action，再 `ninja -j4` 续编（增量，不必 clean 全树）。

不要对同一编译错误做无诊断的自动死循环重启。

### 12.5 磁盘与树体积

| 项 | 内容 |
|----|------|
| 现象 | 文档写预留 150GB；实编树约 60GB 量级（`third_party` 很大），`out` 再数 GB，空闲一度只有约 50GB 仍可继续，但要盯着 |
| 原因 | `gclient sync -D --with_branch_heads --with_tags` 比只拉浅树/单 tag 的嵌入式裁剪树更肥（曾对比自研 M133 embed 约 39GB） |
| 改法 | 按第 2 节命令拉树可以编通；全程 `df` 监控，空闲掉到约 12GB 以下先停、清无关目录再续。不要为了省事 `ninja -t clean` 整树，除非产物已确认损坏 |

### 12.6 并行度（`-j`）与内存

| 项 | 内容 |
|----|------|
| 现象 | 默认 `ninja -j4` 时 8 核机器上只有约 4 路 `clang++` 打满，编得慢；load≈并行数 |
| 原因 | 当初压并行是怕 15G 内存在 CXX/链接阶段 OOM |
| 改法 | 这台编译机（8 核 / 15G）可提到 **`-j6`**：6 路 clang 打满时可用内存大约还剩 5G 量级，比 `-j4` 快一截。`-j8` 更快但 OOM 风险更大，未确认前别用。重启 ninja 时带上 `-j6`，并把 supervisor / 续编脚本里的 `-j4` 一并改掉，避免死后又退回 4 |

调高 `-j` 时要先停掉旧 ninja 再按新并行度重开；`finish_when_aar` / watcher 可能短暂记一条「ninja gone」，这是预期的，按新 `-j` 拉起一次即可，不要当成编译失败去盲重启或改 State=FAILED。

### 12.7 编译命令与产物（实编约定）

```bash
# 在 src/ 下，out 目录名可自定；本次用 out/crwebview_arm64
# 并行度见 12.6：本机用 -j6（勿再写回 -j4）
autoninja -C out/crwebview_arm64 -j6 \
  android_webview/crwebview:crwebkit_aar \
  android_webview/crwebview:webkit_glue_resources \
  # 以及方案第 7 节资源 AAR 所需的 resources 目标
```

主 AAR 出来后再做第 7 节资源 AAR 打包和第 8 节核对。应用接入（第 9 节）等产物核对通过后再做。


### 12.8 Python 3.13 + 系统 protobuf：`FrozenInstanceError`（on_device proto 生成）

| 项 | 内容 |
|----|------|
| 现象 | 编到中段 `ACTION` 跑 `gen_on_device_proto_descriptors.py` 时挂：`AttributeError: module 'google.protobuf.message' has no attribute 'FrozenInstanceError'`，随后 `SystemError`（`google._upb._message` 导入），`FAILED: .../on_device_model_execution_proto_descriptors.cc`，ninja 退出 |
| 原因 | 编译机是 **Python 3.13**，`/usr/local/.../dist-packages` 里装着系统 **protobuf 7.x（带 upb）**。脚本虽然把 Chromium 的 `third_party/protobuf/python` 插到 `sys.path` 前面，但 `_CanImport('google._upb._message')` 仍会拽到系统 upb；系统扩展期望新版 `message.FrozenInstanceError`，和树内旧版 `message.py` 搅在一起就炸 |
| 改法（持久，续编/重启都要带着） | 见下 |

1. 在编译树旁（本次 `/workspace/crwebview-132/`）放隔离包装：

- `python-fix/sitecustomize.py`：启动时去掉 `sys.path` 里含 `dist-packages` / `site-packages` 的项，并 `PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python`
- `bin/python3`（可同时链 `python` / `python3.13`）：导出上述环境变量与 `PYTHONPATH=.../python-fix`，再 `exec /usr/bin/python3`

2. **启动 ninja 的 shell** 必须把 `bin` 放在 `PATH` 最前（supervisor / 续编脚本同样写死），例如：

```bash
export PATH="/workspace/crwebview-132/bin:$PATH"
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
export PYTHONPATH="/workspace/crwebview-132/python-fix${PYTHONPATH:+:$PYTHONPATH}"
# 再 ninja -C out/... -j6 ...
```

3. 先单独跑一遍失败的那条 `python3 .../gen_on_device_proto_descriptors.py ...`，确认生成文件非空（本次约 82KB）再续编。不要对同一 FrozenInstance 错误无包装地盲重启。

同类问题在自研 M133 embed AAR 树上也遇到过，修法相同。


### 12.9 ninja 日志无 FAILED 就静默退出（中段续编）

| 项 | 内容 |
|----|------|
| 现象 | `ninja-build.log` 停在某个 `[done/total]`（本次约 `[5550/9805]`），末尾没有 `FAILED:` / `error:` / `ninja: build stopped`；进程消失，AAR 未出。watch / finish_when_aar 会把 STATE 标成 FAILED |
| 排查 | 1) `pgrep` 确认 ninja 已死；2) 看 `dmesg` 是否有 OOM；3) 核对已知坑的产物是否已在：`color_data.o`、`on_device_model_execution_proto_descriptors.cc`（约 82KB）——若已在，不要当成 12.4/12.8 复发去盲改；4) `free -h`：本机无 swap，`-j6` 多路 clang 时可用内存可能只剩数 GB |
| 原因 | 多为编译进程被杀（内存压力 / 宿主回收）或拉起 ninja 的后台 shell 被收掉，属于运行时中断，不是源码编译错误 |
| 改法 | 保持 `bin/` 在 PATH 前 + `PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python` + `PYTHONPATH=.../python-fix`（见 12.8），用 **`-j6`** 续编（见 12.6）；恢复 `watch_ninja` / `finish_when_aar`。不要对「无 FAILED 的静默死」做无诊断盲重启循环；若同一进度反复静默死且 `dmesg` 确认 OOM，再降到 `-j4` 并记一笔 |


### 12.10 TextureView `draw_functor.cc`：`ScopedAllowBlocking` 私有构造（尾段链接前）

| 项 | 内容 |
|----|------|
| 现象 | 编到尾段（本次约剩余相 `[3745/4255]`）`FAILED: obj/android_webview/libwebviewchromium/draw_functor.o`：`error: calling a private constructor of class 'base::ScopedAllowBlocking'`，连带 private destructor；`ninja: build stopped` |
| 原因 | Chromium 把 `base::ScopedAllowBlocking` 的构造/析构收成 **仅 friend 可实例化**。`android_webview/crwebview/.../draw_functor.cc` 的 `InitializeGLBindings()` 里写了裸的 `base::ScopedAllowBlocking`（加载 `libEGL.so`）。生产路径的 friend 是 `android_webview::ScopedAllowInitGLBindings`（见 `aw_contents.cc` + `thread_restrictions.h`）；同名画图路径的 **test shell**（`android_webview/test/shell/.../context_manager.cc`）用的是 `ScopedAllowBlockingForTesting` |
| 改法 | 把 `draw_functor.cc` 里这一处改成 `base::ScopedAllowBlockingForTesting`（与上游 test shell 同源写法一致）。改完确认 `draw_functor.o` 能编过再 `-j6` 续编；PATH/`bin/`+protobuf 隔离仍按 12.8 带着。不要对同一 private ctor 错误盲重启 |

