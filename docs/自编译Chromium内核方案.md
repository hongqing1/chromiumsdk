# 自编译 Chromium 内核方案（基于 crwebview）

| 项 | 内容 |
|----|------|
| 日期 | 2026-10-30（步骤内嵌实编修正；历史索引见 §12） |
| 来源 | [wuruxu/crwebview](https://github.com/wuruxu/crwebview) `main` 的 `88f8fc85`（2025-04-21，之后没有提交） |
| 现在用的 | 2.0.0，内核 `132.0.6834.86`（从 AAR 里的版本串读出） |
| 这次编 | `132.0.6834.165`，132 分支 Android 稳定版的最后一版（2025-02-04） |
| 应用 | `minSdk` 26（Android 8.0），只出 arm64-v8a |
| 对照 | [crwebview 集成过程与问题](../../../docs/技术设计文档/crwebview集成过程与问题.md)、[低版本 Chrome 内核兼容方案](../../../docs/技术设计文档/低版本chrome内核兼容方案.md) |

继续用 crwebview 的接口和应用里已经接好的 `CrWebViewImpl`，自己从源码编一份换掉 2.0.0。这一轮做三件事：

- 内核从 `132.0.6834.86` 升到 `132.0.6834.165`。同一条分支，补丁基本不用动。
- 修 Android 8：创建就崩、没有 Vulkan 的机器上崩、数据目录和系统 WebView 共用。
- 去掉进页闪黑：`HardwareView` 从 `SurfaceView` 换成 `TextureView`。

仓库里公开的三份补丁比 2.0.0 实际用的旧，直接打上编不出 2.0.0 这套布局，第 3 节先把它们对齐。

### 本轮编译 / 发布状态（2026-10-29–30 Asia/Shanghai）

| 项 | 内容 |
|----|------|
| 状态 | **BOTH_AAR_DONE**（主 AAR：`QueryRenderMode`→GLES；资源 AAR：values 按名合并 + content∪ui R shim） |
| 主 AAR | `crwebview-132.0.6834.165.aar` ~104–105M（含 so + classes + 注入的 `icudtl.dat` / paks / `snapshot_blob_64.bin` / 83 个 `stored-locales`；本树无 `v8_context_snapshot`） |
| 资源 AAR | `crwebview-res-132.0.6834.165.aar` **~409K**（values 按名合并 + grit + shared_with_webview；**content R shim = content∪ui**，含 `R$array`/`ui_com_google_android_gms_fonts_certs*`）。此前 ~140K 残缺包与仅 styles 修好的 ~391K 包均已作废 |
| GitHub Release | https://github.com/hongqing1/chromiumsdk/releases/tag/v132.0.6834.165-arm64 |
| 重建 kit 分支 | https://github.com/hongqing1/chromiumsdk/tree/v132.0.6834.165-arm64（patches / gn / packaging / docs，无完整 Chromium 树） |
| 应用接入 | 第 9 节进行中；换 **主 AAR**（GLES）+ **~409K 资源 AAR** 后再测 |

## 1. 版本

| 候选 | Android 8 | 补丁 | 结论 |
|------|-----------|------|------|
| `132.0.6834.165` | 支持 | 补丁动到的 67 个文件，`.86` 到 `.165` 一个都没变。`001`、`003` 在 `.165` 上 `git apply --check` 通过，`002` 只有 `Profile.java` 一处上下文对不上 | 这次用 |
| `138.0.7204.180` | 支持，是最后一版（2025-07-30） | 跨 6 个里程碑，`002` 这份 61KB 的胶水补丁要逐个文件重做 | 以后再说 |
| 139 及以上 | WebView 最低 Android 10 | — | 不能用 |

两条线都已经没有上游安全补丁。升到 `.165` 只是补上 132 分支 2025-01 中到 2025-02 初的修复，不改变「冻结内核、不能当上架内核」这个前提。

## 2. 环境和源码

编译机用 Linux（Ubuntu 22.04，WSL2 可以）。磁盘留 150GB 以上，内存 32GB 更稳（实编曾在 8 核 / 15G、空闲约 50GB 时编通，全程 `df` 监控；空闲掉到约 12GB 以下先停、清无关目录再续。不要为了省事 `ninja -t clean` 整树，除非产物已确认损坏）。拉 Chromium 源码要走代理。

`gclient sync -D --with_branch_heads --with_tags` 拉下来的树约 60GB 量级（`third_party` 很大），`out` 再数 GB。

```bash
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git ~/depot_tools
export PATH="$PATH:$HOME/depot_tools"

mkdir -p ~/crwebview-132 && cd ~/crwebview-132
fetch --nohooks android
cd src
git fetch origin tag 132.0.6834.165 --no-tags
git checkout -b crwebview-132 132.0.6834.165
gclient sync -D --with_branch_heads --with_tags
./build/install-build-deps.sh --android
gclient runhooks
cat chrome/VERSION
```

`chrome/VERSION` 必须是 `MAJOR=132`、`BUILD=6834`、`PATCH=165`，不是就停。用 `fetch chromium` 拉下来的是桌面树，编不出 WebView。

### 2.1 Python 3.13 + 系统 protobuf 隔离（开编前一次性）

若编译机是 **Python 3.13** 且系统装了 **protobuf 7.x（带 upb）**，`gen_on_device_proto_descriptors.py` 会在中段因 `FrozenInstanceError` / `google._upb._message` 搅树内旧 `message.py` 而失败。在编译树旁（例如 `~/crwebview-132/`）放隔离包装，**启动 ninja 的 shell**（含 supervisor / 续编脚本）把 `bin` 放在 `PATH` 最前：

- `python-fix/sitecustomize.py`：启动时去掉 `sys.path` 里含 `dist-packages` / `site-packages` 的项，并设 `PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python`
- `bin/python3`（可同时链 `python` / `python3.13`）：导出上述环境变量与 `PYTHONPATH=.../python-fix`，再 `exec /usr/bin/python3`

kit 分支已有副本：`scripts/bin/`、`scripts/python-fix/`。复制到编译根后：

```bash
export PATH="/path/to/crwebview-132/bin:$PATH"
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
export PYTHONPATH="/path/to/crwebview-132/python-fix${PYTHONPATH:+:$PYTHONPATH}"
```

先单独跑一遍失败过的 `python3 .../gen_on_device_proto_descriptors.py ...`，确认生成文件非空（约 82KB）再开编。

### 2.2 放入 crwebview 并打三份公开补丁

crwebview 先 fork 到内部 GitLab，后面的改动都提交在 fork 上，下次能原样重编。仓库整个放到 `src/android_webview/crwebview/`，`draw_functor.cc` 里的 include 写的就是这个路径：

```bash
git clone <内部 GitLab>/crwebview.git android_webview/crwebview
# 或上游：git clone https://github.com/wuruxu/crwebview.git android_webview/crwebview
# git -C android_webview/crwebview checkout --detach 88f8fc851879853f51cc02928e95db57fe99fb0a
echo "android_webview/crwebview/" >> .git/info/exclude

git apply android_webview/crwebview/patches/001.android_webview.support_library.patch
git apply --reject android_webview/crwebview/patches/002.android_webview.glue.patch
git apply android_webview/crwebview/patches/003.android_webview.BUILD.gn.patch
```

`002` 会在 `glue/.../Profile.java` 留下一个 `.rej`（`.165` 在 `NonNull` 前多 import 了 `AnyThread`，补丁上下文对不上）。手工把文件开头的五个 `android.webkit.*` import（`CookieManager`、`GeolocationPermissions`、`ServiceWorkerController`、`ValueCallback`、`WebStorage`）换成 `org.chromium.android_crwebview.webkit.*`，再删掉 `.rej`。也可用 kit 的 `patches/chromium/0009-profile-java-import-fix.patch`。除了这一处，其它文件打不上就停，说明这棵树不是 `132.0.6834.165`。

## 3. 补丁和仓库布局对齐

公开的 `002`、`003` 停在 2024-12-18 的布局：`MyDrawFunctor` 在 `com.android.webview.chromium`，native 放在 `android_webview/glue/java/src/draw_glue/`，`webkit_glue_java` 定义在 `android_webview/BUILD.gn`。2025-01-06 的提交 `fix draw_fn implements` 把它们挪进了仓库自己的 `BUILD.gn`。2.0.0 里 `MyDrawFunctor` 在 `org.chromium.android_crwebview.webkit`，用的是新布局，补丁没有跟着更新。按补丁原样编，`gn gen` 会报找不到 `glue/java/src/com/android/webview/chromium/MyDrawFunctor.java`。

统一按仓库布局，打完补丁后改这几处（kit 对应 `patches/chromium/0010`–`0014`、`patches/crwebview/0020`）：

| 文件 | 补丁里写的 | 改成 |
|------|-----------|------|
| `android_webview/BUILD.gn` | `003` 新增的 `draw_fn_impl_jni_headers`、`draw_fn_impl_java`、`webkit_glue_java`、`webkit_glue_resources` | 整段删掉，用 `//android_webview/crwebview:` 下的同名目标 |
| `android_webview/BUILD.gn` 的 `libwebviewchromium_tmpl` | `sources` 是 `glue/java/src/draw_glue/*.cc`，`deps` 有 `":draw_fn_impl_jni_headers"` | `sources` 换成 `//android_webview/crwebview/java/src/draw_fn/` 下的 `overlays_manager.cc`、`allocator.cc`、`draw_functor.cc`，`deps` 换成 `"//android_webview/crwebview:draw_fn_impl_jni_headers"` |
| `android_webview/BUILD.gn` 的 `browser_java` | 多加了源文件 `java/src/org/chromium/android_crwebview/webkit/JavascriptInterface.java`，`deps` 有 `":webkit_glue_java"` | 删掉这行源文件。这个类已经在 `webkit_glue_java` 里，两处都编会重复。`deps` 换成 `"//android_webview/crwebview:webkit_glue_java"` |
| `android_webview/glue/BUILD.gn` | `"//android_webview:webkit_glue_java"` | `"//android_webview/crwebview:webkit_glue_java"` |
| `glue/.../WebViewChromiumAwInit.java` | 直接用 `MyDrawFunctor`，没有 import | 加 `import org.chromium.android_crwebview.webkit.MyDrawFunctor;` |
| `crwebview/BUILD.gn` 的 `webkit_glue_java` | `sources` 里也列了 `MyDrawFunctor.java` | 删掉这一行，只留在 `draw_fn_impl_java` |
| `crwebview/BUILD.gn` 的 `crwebkit_aar` | `output` 是 `android_crwebview_webkit.WebView-v2.0.0.aar` | 改成 `crwebview-132.0.6834.165.aar` |

布局挪走 `webkit_glue_java` 后，`support_library` 等目标仍可能写旧 label `//android_webview:webkit_glue_java`。在 `android_webview/BUILD.gn` **加别名**，不要把源再拷回旧位置：

```gn
# Alias: webkit_glue_java lives in crwebview/ after layout realignment.
java_group("webkit_glue_java") {
  deps = [ "//android_webview/crwebview:webkit_glue_java" ]
}
```

`js_prompt.xml`、`webview_find` 已在 `//android_webview/crwebview:webkit_glue_resources`。从 `android_webview:resources` 的 `sources` 里**删掉这两项**，只保留 crwebview 侧，并注释标明归属；否则资源阶段会重复同名 layout。

改完 `gn gen` 不报重复定义、不报找不到目标，再往下做。`javac` 报找不到 `org.chromium.android_crwebview.webkit.*` 时，给报错的那个目标加 `//android_webview/crwebview:webkit_glue_java`。`webkit_glue_java` 不依赖 `browser_java`，不会成环。

## 4. 修 Android 8

| 现象 | 原因 | 改法 |
|------|------|------|
| Android 8、9、10 一创建就 `NoSuchMethodError` | `WebView.java` 构造函数直接调用 `getImportantForContentCapture()`，API 30 才有（issue #9） | 包上版本判断 |
| 没有 Vulkan 1.1 的机器一初始化就崩在 `CHECK` | `draw_functor.cc` 只有 `MyDrawFunctorVulkan`；`QueryRenderMode` 若写死 VULKAN，GpuInit 仍会走 Vulkan | 补回 GLES；`USE_VULKAN=false`；`QueryRenderMode` 按 `g_use_vulkan` 返回 |
| Android 8 上数据目录和系统 WebView 共用 | 胶水在 API 28 以下不读 `WebView.setDataDirectorySuffix`，走 AndroidX 配置。`WebViewDelegateWrapper.getDataDirectorySuffix()` 写死返回 `""`。没有后缀就是 `app_webview` | 所有版本都从 crwebview 的 `WebViewFactory` 取后缀 |

### 4.1 构造函数

`java/src/org/chromium/android_crwebview/webkit/WebView.java`：

```java
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
    if (getImportantForContentCapture() == IMPORTANT_FOR_CONTENT_CAPTURE_AUTO) {
        setImportantForContentCapture(IMPORTANT_FOR_CONTENT_CAPTURE_YES);
    }
}
```

上面的 `getImportantForAutofill` 是 API 26，不用包。`onCreateVirtualViewTranslationRequests` 这类 API 31 的方法只是覆写，低版本系统不会调用，不用动。真机上再报 `NoSuchMethodError` 或 `NoClassDefFoundError`，同样包版本判断。

### 4.2 GLES 绘制（与 test shell 对齐）

132 树里 `android_webview/test/shell/src/draw_fn/context_manager.cc` 同时有 `ContextManagerGL` 和 `ContextManagerVulkan`，按 `use_vulkan` 二选一。crwebview 的 `draw_functor.cc` 就是从它改的，只留了 Vulkan 那一半。按下面做齐整条 GLES 路径（kit：`0022`/`0023`/`0026`）：

1. 把 `ContextManagerGL` 整个类拷进 `crwebview/java/src/draw_fn/draw_functor.cc`，改名 `MyDrawFunctorGL`，基类换成 `DrawFunctor`。`InitializeGLBindings`、`GetConfig`、`DoCreateContext`、`DestroyContext`、`MakeCurrent` 原样带上。

2. `InitializeGLBindings()` 里加载 `libEGL.so` 时，写成 **`base::ScopedAllowBlockingForTesting`**（与上游 test shell 一致）。Chromium 已把 `base::ScopedAllowBlocking` 收成仅 friend 可实例化；裸写会在尾段编 `draw_functor.o` 时报 private constructor。生产路径的 friend 是 `android_webview::ScopedAllowInitGLBindings`，embed 画图路径用 Testing 变体。

3. `Draw` 里在 `draw_gl` 之前把表面清成透明。我们的表面下面没有别的内容，不清的话透明区域是上一帧残留：

```cpp
  MakeCurrent();
  glDisableFn(GL_SCISSOR_TEST);
  glClearColorFn(0, 0, 0, 0);
  glClearFn(GL_COLOR_BUFFER_BIT);
  AwDrawFn_DrawGLParams params{kAwDrawFnVersion};
```

`glDisableFn`、`glClearColorFn`、`glClearFn` 照 `glReadPixelsFn` 的写法，在 `InitializeGLBindings` 里用 `AssignProc` 取。

4. JNI 入口按参数分开，Vulkan 只在要用时才初始化：

```cpp
static jlong JNI_MyDrawFunctor_GetDrawFnFunctionTable(JNIEnv* env,
                                                       jboolean use_vulkan) {
  if (use_vulkan) {
    // 原来创建 vulkan_implementation_ 和 device_queue_ 的那段放进这里
  }
  draw_fn::SetDrawFnUseVulkan(use_vulkan);
  return reinterpret_cast<intptr_t>(draw_fn::GetDrawFnFunctionTable());
}

static jlong JNI_MyDrawFunctor_Init(JNIEnv* env, jboolean use_vulkan) {
  DrawFunctor* manager = nullptr;
  if (use_vulkan) {
    manager = new draw_fn::MyDrawFunctorVulkan;
  } else {
    manager = new draw_fn::MyDrawFunctorGL;
  }
  return reinterpret_cast<intptr_t>(manager);
}
```

5. `MyDrawFunctor.java` 两处 `true` 换成一个常量：

```java
private static final boolean USE_VULKAN = false;

public static long getDrawFnFunctionTable() {
    return MyDrawFunctorJni.get().getDrawFnFunctionTable(USE_VULKAN);
}

public MyDrawFunctor() {
    mMyDrawFunctor = MyDrawFunctorJni.get().init(USE_VULKAN);
}
```

6. 在 `allocator.cc` 里与 test shell 对齐（补丁 `patches/crwebview/0026-allocator-query-render-mode-gles.patch`）：

```cpp
bool g_use_vulkan = false;

AwDrawFnRenderMode QueryRenderMode() {
  return g_use_vulkan ? AW_DRAW_FN_RENDER_MODE_VULKAN
                      : AW_DRAW_FN_RENDER_MODE_OPENGL_ES;
}
```

仅改 Java `USE_VULKAN` / `SetDrawFnUseVulkan` 而不改 `QueryRenderMode` 时，`AwDrawFnImpl::IsUsingVulkan()` 仍为 true，`aw_main_delegate` 仍会追加 `kWebViewDrawFunctorUsesVulkan`，GpuInit 在无 Vulkan 1.1 的机器上 `CHECK`。不要为躲 CHECK 去关整棵 GPU 进程。

所有版本都走 GLES，只维护一条绘制路径。Android 8、9 的系统界面本来就是 GL 渲染，上游测试壳默认也是 GL。Vulkan 的代码留着不删。Android 11 以上哪台机器 GLES 有问题，再按 `SDK_INT` 打开 Vulkan。

GL 上下文的创建、每帧绘制、销毁都在主线程，和 2.0.0 现在一样（`HardwareView` 里都是 `ThreadUtils.postOnUiThread`）。不要一半放主线程、一半放 `RenderThreadInstr`。

### 4.3 数据目录

`002` 里 `WebViewChromiumFactoryProvider.java` 取后缀的地方，去掉版本分支：

```java
String dataDirectorySuffix = WebViewFactory.getDataDirectorySuffix();
AwBrowserProcess.loadLibrary(
        dataDirectoryBasePath, cacheDirectoryBasePath, dataDirectorySuffix);
```

这里的 `WebViewFactory` 是 `org.chromium.android_crwebview.webkit.WebViewFactory`。`WebViewDelegateWrapper.getDataDirectorySuffix()` 也改成返回 `WebViewFactory.getDataDirectorySuffix()`，不要写死 `""`。

应用侧设成 `crwebview`（见第 9 节），目录就是 `app_webview_crwebview`，和系统 WebView 的 `app_webview` 分开。不分开的话，实验室开关一切换，两个不同版本的 Chromium 读同一份 Cookie、LocalStorage、IndexedDB，高版本写过的库低版本打不开。

### 4.4 so 能在 API 26 上加载

`132.0.6834.165` 的默认配置里没有启用重定位打包，`lld_pack_relocations` 和 `lld_relr_relocations` 都要显式加进 configs 才生效。不要把 `lld_relr_relocations` 加到 `libwebviewchromium` 上。RELR 在 API 28 以下加载不了。编完用 `llvm-readelf -d` 看，不能有 `RELR` 和 `ANDROID_RELR`（第 8 节）。

## 5. 去掉进页闪黑

`HardwareView` 继承 `SurfaceView`，`setZOrderMediaOverlay(true)`。它的表面是窗口之外的独立图层，排在窗口后面。窗口在 WebView 的位置挖一个透明洞把它露出来。表面画出第一帧之前，洞里是黑的。WebView 自己的背景画在窗口里，正好被挖掉。应用在 `onPageStarted` 把背景设透明之后，页面没画到的透明像素在洞里也显示成黑色。应用侧加背景、加前景都改不掉，之前试过。

改成 `TextureView`。它的内容由窗口自己合成，第一帧之前什么都不画，露出来的是 WebView 后面的背景。透明像素透出下面的 View，不会变黑。

`WebView.java` 里的 `HardwareView` 改成下面这样。没有加进 View 树的 `mOverlaysSurfaceView` 一起删掉，它的 native `SetOverlaysSurface` 本来就是空的。`sRenderThread`、`sRenderThreadHandler` 没有真正用到（handler 绑的是主线程 Looper），也删掉，构造函数不再要 `Looper`。

```java
private static class HardwareView extends TextureView
        implements TextureView.SurfaceTextureListener {
    private int mWidth;
    private int mHeight;
    private int mLastScrollX;
    private int mLastScrollY;
    private boolean mHaveSurface;
    private Surface mSurface;
    private final MyDrawFunctor mDrawFunctor;

    HardwareView(Context context) {
        super(context);
        mDrawFunctor = new MyDrawFunctor();
        setOpaque(false);
        setSurfaceTextureListener(this);
    }

    @Override
    public void onSurfaceTextureAvailable(SurfaceTexture texture, int width, int height) {
        mSurface = new Surface(texture);
        mWidth = width;
        mHeight = height;
        mHaveSurface = true;
        mDrawFunctor.setSurface(mSurface, width, height);
        ((View) getParent()).invalidate();
    }

    @Override
    public void onSurfaceTextureSizeChanged(SurfaceTexture texture, int width, int height) {
        mWidth = width;
        mHeight = height;
        mDrawFunctor.setSurface(mSurface, width, height);
    }

    @Override
    public boolean onSurfaceTextureDestroyed(SurfaceTexture texture) {
        mHaveSurface = false;
        mDrawFunctor.setSurface(null, 0, 0);
        mSurface.release();
        mSurface = null;
        return true;
    }

    @Override
    public void onSurfaceTextureUpdated(SurfaceTexture texture) {}

    void updateScroll(int x, int y) {
        mLastScrollX = x;
        mLastScrollY = y;
    }

    void drawWebViewFunctor(int functor) {
        if (!mHaveSurface) {
            return;
        }
        ThreadUtils.postOnUiThread(() -> {
            if (!mHaveSurface) {
                return;
            }
            mDrawFunctor.sync(functor, false);
            mDrawFunctor.draw(mWidth, mHeight, mLastScrollX, mLastScrollY, false);
        });
    }
}
```

`onSurfaceTextureDestroyed` 里的 `setSurface(null, ...)` 必须同步做完再返回 `true`，返回之后 `SurfaceTexture` 就释放了。2.0.0 的 `surfaceDestroyed` 是 post 出去的，会在表面释放之后才销毁 GL/Vulkan 上下文。已经 post 出去的绘制在 runnable 里再判断一次 `mHaveSurface`。

构造函数里 `new HardwareView(context, mWebViewThread)` 改成 `new HardwareView(context)`，`addView` 和滚动时的 `setTranslationX/Y` 不变。`readbackQuadrantColors`、`isReadyToRender`、`setReadyToRenderCallback`、`getOverlaysView` 没有调用方的就删掉。

代价：

- 多一次 GPU 合成，触摸到上屏大约晚一帧。
- `TextureView` 只在硬件加速的窗口里画。WebView 和它的父 View 不能设 `LAYER_TYPE_SOFTWARE`。应用里设软件层的是引导层、气泡、GIF 和分隔线，都不包 WebView。
- `TextureView` 在窗口缓冲里，按窗口截图（`PixelCopy` 传窗口）能截到页面。`View.draw` 画到软件 `Canvas` 上仍然截不到，要用 `TextureView.getBitmap()`。回放截屏走的是哪一种，换包后再看。

## 6. 同一批文件里顺手改

| 位置 | 改法 | 原因 |
|------|------|------|
| `WebView.java`、`WebViewDelegateWrapper.java`、`002` 里的 `MyDrawFnAccess` | 删掉 `Log.i("crWebView", ...)`。绘制路径上的那些每帧都打 | 仓库里有五十多处，`drawWebViewFunctor` 每帧打两到四条 logcat |
| `java/src/org/chromium/build/BuildConfig.java` | `ENABLE_DEBUG_LOGS = false`，`VERSION_CODE` 换成这次的日期 | 手写的这份是 `true` |
| `WebViewDelegateWrapper.isMultiProcessEnabled()` | 这轮保持 `false` | 渲染进程在应用进程里，页面崩溃会带崩应用。打开多进程要另测沙箱进程，不放进这一轮 |

## 7. args.gn 和编译

### 7.1 gperf 3.2 + clang（开编前）

编译机若是 **gperf 3.2.x**（`gperf --version` → 3.2.1），生成的 `color_data.cc` 会在中段因 fallthrough 注解夹在 `#endif` 与 `case` 之间被 clang `-Wimplicit-fallthrough` 拒绝。三处一起改（kit：`patches/chromium/0012-color-data-fallthrough.patch`）：

1. `third_party/blink/renderer/platform/color_data.gperf` 头里（已有 shorten-64 的 pragma 旁）加上：

```c
#pragma clang diagnostic ignored "-Wimplicit-fallthrough"
#pragma GCC diagnostic ignored "-Wimplicit-fallthrough"
```

2. `third_party/blink/renderer/build/scripts/gperf.py`：在把 `/*FALLTHROUGH*/` 换成 `[[fallthrough]];` **之前**，先删掉 gperf 3.2 插入的整段 `#if / [[fallthrough]] / #elif / __attribute__ / #endif`，只留脚本写在 `case` 正上方的那一条注解。

3. 若 `out/.../gen/.../color_data.cc` 已经生成坏了：按同样规则改生成文件，或删掉该 gen 文件让 ninja 重跑 `color_data` action，再续编（增量，不必 clean 全树）。

### 7.2 args.gn

写到 `src/out/crwebview_arm64/args.gn`（或直接拷 kit 的 `gn/args.gn`）：

```gn
target_os = "android"
target_cpu = "arm64"
is_debug = false
is_component_build = false
is_official_build = false
symbol_level = 0
blink_symbol_level = 0
proprietary_codecs = true
ffmpeg_branding = "Chrome"
use_official_google_api_keys = false
treat_warnings_as_errors = false
```

`proprietary_codecs` 和 `ffmpeg_branding` 必须一起开，否则课件里的 H.264、AAC 没有画面。`is_official_build` 先关，不做 LTO。不填任何 Google API key。链接时内存不够，在 `args.gn` 加 `concurrent_links = 1` 再 `gn gen`。

### 7.3 并行度与启动 ninja

在 8 核 / 15G 这台机上用 **`-j6`**：6 路 clang 打满时可用内存大约还剩 5G 量级，比 `-j4` 快；`-j8` 更快但 OOM 风险更大，未确认前别用。supervisor / 续编脚本里的并行度也写成 `-j6`，避免死后退回 4。调高 `-j` 时先停掉旧 ninja 再按新并行度重开。

启动前确认 §2.1 的 `bin/` + protobuf 隔离已在 `PATH`：

```bash
gn gen out/crwebview_arm64
gn ls out/crwebview_arm64 | grep -E 'crwebview|autofill.*resources|media.*resources'
autoninja -C out/crwebview_arm64 -j6 \
  //android_webview/crwebview:crwebkit_aar \
  //android_webview/crwebview:webkit_glue_resources \
  //android_webview:crwebview_ui_android_resources \
  //android_webview:crwebview_content_resources \
  //android_webview:crwebview_embedder_support_resources \
  //android_webview:resources
```

`gn ls` 里查到的 autofill、media 资源目标也加进 `autoninja`。不要编 `system_webview_apk`、Trichrome，也不要 `autoninja` 不带目标。

若 `ninja-build.log` 停在某个 `[done/total]`、末尾没有 `FAILED:` / `error:` / `ninja: build stopped`、进程消失且 AAR 未出：先 `pgrep` 确认 ninja 已死，看 `dmesg` 是否 OOM，再核对 `color_data.o`、`on_device_model_execution_proto_descriptors.cc`（约 82KB）是否已在——已在则不要当成 gperf/protobuf 复发去盲改。保持 PATH/`bin/` + `-j6` 续编；同一进度反复静默死且 `dmesg` 确认 OOM 时再降到 `-j4`。不要对无诊断错误做盲重启循环。

主 AAR 出来后再做下面资源 AAR 打包和第 8 节核对。

### 7.4 资源 AAR（按名合并 + content∪ui R shim）

主 AAR 不带资源，`resource_included_patterns` 写的是 `not_include_any_resources`。主包里引用到的每个 `R` 包名都要有资源。2.0.0 的主包引用了七个，只给了四个资源包：

| `R` 包名 | 2.0.0 | 资源目标 |
|----------|-------|---------|
| `org.chromium.ui` | `ui-debug.aar` | `crwebview_ui_android_resources` |
| `org.chromium.content` | `content-debug.aar` | `crwebview_content_resources` |
| `org.chromium.components.embedder_support.delegate` | `embedder_support_resources-debug.aar` | `crwebview_embedder_support_resources` |
| `org.chromium.android_webview` | `android_webview_resources-debug.aar` | `//android_webview:resources` |
| `org.chromium.android_crwebview.webkit` | 没有 | `webkit_glue_resources`（`js_prompt`、`webview_find`） |
| `org.chromium.components.autofill` | 没有 | autofill 的 `android_resources` |
| `org.chromium.media` | 没有 | media 的 `android_resources` |

缺的三个在 2.0.0 上没崩，是因为还没走到：`prompt()` 弹框、自动填充下拉、部分媒体控件。编完先列一遍主包实际引用的 `R`：

```bash
mkdir -p /tmp/crwebkit && cd /tmp/crwebkit
unzip -o -q ~/crwebview-132/src/out/crwebview_arm64/crwebview-132.0.6834.165.aar classes.jar
unzip -o -q classes.jar -d classes
grep -rhoa 'org/chromium/[a-z0-9_/]*/R\$[a-z]*' classes | sed 's/\$.*//' | sort -u
```

七个包名合成一个资源 AAR：`crwebview-res-132.0.6834.165.aar`。

AGP 只按 AAR 自己的 `namespace` 生成一个 `R`，资源合进一个包之后，`org.chromium.ui.R` 这些类不会自动出现。2.0.0 分成四个包，就是为了让每个包名各有一个 `R`。合成一个的做法是在这个 AAR 里放七个转发用的 `R` 类，字段从合并后的 `R` 取值。内核代码读 `R` 用的是 `getstatic`（`DeviceFormFactor` 里是 `getstatic org/chromium/ui/R$integer.min_screen_width_bucket`），没有把 id 编成常量，所以运行时转发能生效。

用一个 Android library 模块打：

| 项 | 内容 |
|----|------|
| `namespace` | `org.chromium.crwebview.res`，不和上面七个包名重复 |
| `minSdk` | 26 |
| `src/main/res` | 七个资源目标在 `out/crwebview_arm64/gen/` 下产出的 res，**按资源名合并**（见下） |
| `src/main/java` | 下面脚本生成的七个 `R.java`（**content = content∪ui**） |

#### 合并 values XML（按资源名，禁止路径覆盖）

七个资源目标的 `values/styles.xml`、`values/dimens.xml` 等**相对路径同名**。对 `res/` 做简单 `cp` / last-write-wins 时，后拷的 `android_webview` 几乎空 `WebViewBaseTheme` 会盖掉先拷的 `ui` 完整 styles，应用侧 `process*Resources` 随即失败。

按下面做：

1. 用 kit `packaging/merge_res_from_sources.py`：同路径 values XML **按资源名合并**（同名同内容保留一份；同名异内容停下来查）；非 values 文件仍按路径拷贝。
2. 一并拉入 `components/browser_ui/.../shared_with_webview` 的 dimens（如 `chip_icon_size`），以及 layout 引用的 grit 字符串 zip（`crwebview_*_strings_grd.resources.zip`）。
3. 收尾走 `packaging/package_res_aar_finish.sh`（可 `aapt2 link`；缺宿主 AppCompat 属性时回退合成非 final 的 NS `R`）。AppCompat stub **不进** AAR。
4. 不对缺失 style 做空壳补丁。完整 res AAR 约 **409K**（含 content∪ui R shim）。残缺 last-write-wins ~140K 与仅 styles 修好的 ~391K 均作废，不要再分发。

重建 kit：https://github.com/hongqing1/chromiumsdk/tree/v132.0.6834.165-arm64 `packaging/`。

#### 生成 R 转发类（content 必须 content∪ui）

转发类按七个资源目标的 `R.txt` 生成。`R.txt` 在 `out/crwebview_arm64/gen/` 下，用 `find out/crwebview_arm64/gen -name '*R.txt'` 找到这七个目标对应的那份。

Chromium 的 `content_java` 会把传递依赖的 ui 资源合并进 **content.R**（例如 `ui_com_google_android_gms_fonts_certs*` 定义在 ui 的 `font_certs.xml`，运行时由 `AndroidFontLookupImpl` 经 `org.chromium.content.R` 读取）。shim 必须对 content 传 `CONTENT_RTXT+UI_RTXT`；只按 content 自己的 R.txt 生成时，jar 里没有 `org/chromium/content/R$array`，进页字体会 `NoClassDefFoundError`。不要只在应用侧改 import / 反射绕开，也不要只补空的 `R$array`。

```python
#!/usr/bin/env python3
# 用法：gen_r_shims.py <输出目录> <包名>=<R.txt>[+<R.txt>...] ...
# 多份 R.txt 用 + 并集；content 须 content∪ui（与 packaging/gen_r_shims.py 一致）
import os
import sys
from collections import defaultdict

NS = 'org.chromium.crwebview.res'

out = sys.argv[1]
for arg in sys.argv[2:]:
    pkg, rtxts = arg.split('=', 1)
    types = defaultdict(list)
    seen = defaultdict(set)
    for rtxt in rtxts.split('+'):
        rtxt = rtxt.strip()
        if not rtxt:
            continue
        with open(rtxt) as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3:
                    kind, rtype, name = parts[0], parts[1], parts[2]
                    if name in seen[rtype]:
                        continue
                    seen[rtype].add(name)
                    types[rtype].append((kind, name))
    lines = [f'package {pkg};', '', 'public final class R {']
    for rtype in sorted(types):
        lines.append(f'    public static final class {rtype} {{')
        for kind, name in types[rtype]:
            lines.append(f'        public static {kind} {name} = {NS}.R.{rtype}.{name};')
        lines.append('    }')
    lines.append('}')
    pkg_dir = os.path.join(out, *pkg.split('.'))
    os.makedirs(pkg_dir, exist_ok=True)
    with open(os.path.join(pkg_dir, 'R.java'), 'w') as f:
        f.write('\n'.join(lines) + '\n')
```

```bash
python3 gen_r_shims.py crwebview-res/src/main/java \
  org.chromium.ui=<ui 的 R.txt> \
  org.chromium.content=<content 的 R.txt>+<ui 的 R.txt> \
  org.chromium.components.embedder_support.delegate=<embedder_support 的 R.txt> \
  org.chromium.android_webview=<android_webview 的 R.txt> \
  org.chromium.android_crwebview.webkit=<webkit_glue_resources 的 R.txt> \
  org.chromium.components.autofill=<autofill 的 R.txt> \
  org.chromium.media=<media 的 R.txt>
```

`kind` 是 `int` 或 `int[]`，`styleable` 的数组和下标一起转发（`org.chromium.ui` 用到了 `R$styleable`）。字段不加 `final`，`R` 的值要等应用打包时才定。转发类引用了合并 res 里没有的名字时，`compileReleaseJavaWithJavac` 会报错，说明 res 少拷了一份。重建后 `jar tf` 应有 `org/chromium/content/R$array.class`，`javap` 可见三个 `ui_com_google_android_gms_fonts_certs*`。

`assembleRelease` 出来的 AAR，`classes.jar` 里有七个包名的 `R` 转发类，没有 `org/chromium/crwebview/res/R.class`，那个由应用打包时生成。资源 AAR 和主 AAR 必须同一棵树、同一次编译。

应用现在 `minifyEnabled` 是 false，转发类原样进 dex。以后开混淆，R8 会把这些 `R` 合并掉，内核的 `getstatic` 对不上字段。开的时候按上面扫出来的每个包名在 proguard 规则里保留类和字段，2.0.0 的七个是：

```
-keep class org.chromium.ui.R { *; }
-keep class org.chromium.ui.R$* { *; }
-keep class org.chromium.content.R { *; }
-keep class org.chromium.content.R$* { *; }
-keep class org.chromium.components.embedder_support.delegate.R { *; }
-keep class org.chromium.components.embedder_support.delegate.R$* { *; }
-keep class org.chromium.android_webview.R { *; }
-keep class org.chromium.android_webview.R$* { *; }
-keep class org.chromium.android_crwebview.webkit.R { *; }
-keep class org.chromium.android_crwebview.webkit.R$* { *; }
-keep class org.chromium.components.autofill.R { *; }
-keep class org.chromium.components.autofill.R$* { *; }
-keep class org.chromium.media.R { *; }
-keep class org.chromium.media.R$* { *; }
```

主 AAR 不并进来。它是 GN 的直接产物，编完注入资产后约 104–105M，并进来就要每次重打 so 和 assets，`md5` 也对不上 GN 出的那份。最后放进应用的是两个文件。

## 8. 核对

| 项 | 怎么看 |
|----|--------|
| 内核版本 | `classes.jar` 里能搜到 `132.0.6834.165`，搜不到 `132.0.6834.86` |
| ABI | AAR 的 `jni/` 里只有 `arm64-v8a` |
| 布局 | 有 `org/chromium/android_crwebview/webkit/WebView.class`、`MyDrawFunctor.class`；没有 `com/android/webview/chromium/MyDrawFunctor.class` |
| GLES | `javap -c` 看 `MyDrawFunctor.class`，`init`、`getDrawFnFunctionTable` 传的是 `false`（`iconst_0`）。`QueryRenderMode` 读 `g_use_vulkan`（`llvm-objdump -d allocator.o` 为 `ldrb w0, [g_use_vulkan]`，不是常量 VULKAN）。Android 8 真机 logcat 里没有 `Failed to create Vulkan` / `gpu_init.cc Check failed` |
| 重定位 | `llvm-readelf -d libwebviewchromium.so` 里没有 `RELR`、`ANDROID_RELR` |
| assets | `icudtl.dat`、`resources.pak`、`chrome_100_percent.pak`、`snapshot_blob_64.bin`、`stored-locales/`（本树 **无** `v8_context_snapshot_64.bin`，核对时勿当失败） |
| 资源 AAR | 只有一个 `crwebview-res-132.0.6834.165.aar`（完整包约 **409K**）。清单 `package` 是 `org.chromium.crwebview.res`。`classes.jar` 里有第 7 节列出的每个包名的 `R` 转发类（含 `org/chromium/content/R$array.class`），主 AAR 里没有任何 `R.class`。AAR 内 `values/styles.xml` 须含 ui 侧完整 theme（不止 `WebViewBaseTheme`） |
| 日志 | `classes.jar` 里搜不到 `drawWebViewFunctor STEP` |

## 9. 换进应用

接入在 `crwebview` 分支，`WebViewWrapper`、实验室开关、JSB 反射都不改。

**进度（2026-10-30）：** 第 9 节接入进行中。资源 AAR（~409K，content∪ui）与主 AAR（QueryRenderMode→GLES）均已就绪；换两包后再在真机（含 MI PAD 4 / API 27）验证。

| 位置 | 改法 |
|------|------|
| `common/web/libs/crwebview/` | 删掉 2.0.0 的五个文件，只放 `crwebview-132.0.6834.165.aar` 和 `crwebview-res-132.0.6834.165.aar`。`app/crwebview.gradle` 按 `*.aar` 收，改名不用动脚本。`common/web` 继续 `compileOnly`，`app/crwebview.gradle` 继续 `implementation` |
| `app/crwebview.gradle` | `noCompress 'bin', 'pak', 'dat'`。本地 2.0.0 的 APK 里 `icudtl.dat` 是压缩的，内核按文件描述符映射它 |
| `CrWebViewImpl` | 类里加静态块，在碰任何 crwebview 静态方法之前设后缀。`setWebContentsDebuggingEnabled` 也会初始化内核，所以不能放在 `createWebView` 里 |
| `CrWebViewImpl.createWebView` | 不加前景遮罩。`onPageStarted` 里设透明背景保持不变 |
| `buildSrc` | R8 `8.6.17` 放在 AGP 7.4.2 之前，不变 |
| 清单 | `MetricsOptOut=true`、`EnableSafeBrowsing=false`、`RECORD_VIDEO` 的 `tools:node="remove"` 不变 |

```java
static {
    WebView.setDataDirectorySuffix("crwebview");
}
```

应用打包报 `Duplicate class org.chromium.ui.R` 这一类错，说明还有别的依赖的 `namespace` 也是这七个包名之一，2.0.0 的资源包没删干净时会出现。

这里的 `WebView` 是 `org.chromium.android_crwebview.webkit.WebView`。内核初始化之后再调会抛 `IllegalStateException`。`CrWebViewImpl` 是应用里唯一引用 crwebview 类的地方，放在它的静态块里就够早。

切到新目录后，两个内核的 Cookie 和 LocalStorage 不再共用，网页里的登录状态要靠应用重新注入。装过 2.0.0 的测试机换包前清一次应用数据，2.0.0 的数据混在 `app_webview` 里。

## 10. 真机验证

| 机器 | 看什么 |
|------|--------|
| Android 8.0 / 8.1 arm64 学习机 | 创建不崩；进微课、直播、播放器有画面；JSB 同步返回和异步回调；`app_webview_crwebview` 已经生成 |
| Android 9、10 | 同上 |
| 华为 GOT-W09（Android 11，2.0.0 跑通过的那台） | 改成 GLES 之后微课、选文件、全屏、JSB 不回退 |
| MI PAD 4（API 27） | 无 `Failed to create Vulkan` / GpuInit CHECK；字体路径无 `R$array` 崩溃 |
| 闪黑 | Android 8 和 11 各录一段 `adb shell screenrecord`，进微课逐帧看，没有黑帧 |
| 绘制 | 长页面上下滑动不错位；全屏视频进出；WebView 上面弹对话框、浮层 |
| 资源 | `alert`、`confirm`、`prompt`；输入框的自动填充下拉；页面里的音视频控件 |
| 开关 | 实验室开关来回切几次，不崩；系统 WebView 的 `app_webview` 不被改写 |
| 截图 | 回放截屏重测一遍 |
| 性能 | 2560×1600 平板上滑动帧率，和 2.0.0 对比内存 |

Chrome 58、Chrome 74 那几台工单机，用这包在原设备上再打开一次课程和希沃画布。

## 11. 这一轮不做

| 项 | 原因 |
|----|------|
| 升到 138 | Android 8 能支持到 138，但 `002` 要跨 6 个里程碑重做。先把这版在 Android 8 上跑通 |
| 32 位 | 只编 arm64。32 位学习机仍走系统 WebView，低版本问题还在 |
| 打开多进程 | 见第 6 节 |
| 去掉 so 里的联网地址 | 目前靠清单关使用统计和安全浏览、不填 API key。so 里的 `clients2.google.com` 等地址还在，单独再做 |
| 许可 | 仓库和 AAR 里没有 Chromium 的 LICENSE / NOTICE，上架前要补 |
| 对外发 `common/web` | 这些 AAR 不在发布的 web 模块里，SDK 使用方开着开关一创建就崩，要单独处理 |
| 三星 Android 16 SIGTRAP | 崩在系统 WebView，不是这版的目标 |

## 12. 历史变更索引

实编修正已写入上文对应步骤；本表仅作追溯。kit 补丁见 https://github.com/hongqing1/chromiumsdk/tree/v132.0.6834.165-arm64 。

| 原编号 | 写入步骤 | 摘要 | 日期 / 线索 |
|--------|----------|------|-------------|
| 12.1 | §2.2 | `002` → `Profile.java` import 手工换 / `0009` | 2026-10-29 |
| 12.2 | §3 | `webkit_glue_java` 别名 `java_group` | 2026-10-29 |
| 12.3 | §3 | 从 `android_webview:resources` 去掉 `js_prompt` / `webview_find` | 2026-10-29 |
| 12.4 | §7.1 | gperf 3.2 fallthrough → `0012` | 2026-10-29 |
| 12.5 | §2 | 磁盘监控；勿盲目 `ninja -t clean` | 2026-10-29 |
| 12.6 | §7.3 | `-j6`（8 核 / 15G） | 2026-10-29 |
| 12.7 | §7.3 | `autoninja -j6` 目标列表 | 2026-10-29 |
| 12.8 | §2.1 | PY3_PROTO 隔离 `scripts/bin` + `python-fix` | 2026-10-29 |
| 12.9 | §7.3 | 无 FAILED 静默退出 → 查 OOM / 续编 | 2026-10-29 |
| 12.10 | §4.2 | `ScopedAllowBlockingForTesting` | 2026-10-29 |
| 12.11 | §7.4 | values 按名合并；`merge_res_from_sources.py`（`e1dcc89`） | 2026-10-29 |
| 12.12 | §7.4 | content R shim = content∪ui；res ~409K | 2026-10-30 |
| 12.13 | §4.2 | `QueryRenderMode`↔`g_use_vulkan`；补丁 `0026`（`921bb64`） | 2026-10-30 |
