# 自编译 Chromium 内核方案（基于 crwebview）

| 项 | 内容 |
|----|------|
| 日期 | 2026-10-28（编译踩坑补记 2026-10-29；§12.8–12.12 见下；**§12.13 QueryRenderMode↔g_use_vulkan / GLES**，主 AAR 重编上传 2026-10-30） |
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
| 状态 | **BOTH_AAR_DONE**（主 AAR 已按 §12.13 重编：QueryRenderMode→GLES） |
| 主 AAR | `crwebview-132.0.6834.165.aar` ~105M（含 so + classes + 注入的 `icudtl.dat` / paks / `snapshot_blob_64.bin` / 83 个 `stored-locales`；本树无 `v8_context_snapshot`） |
| 资源 AAR | `crwebview-res-132.0.6834.165.aar` **~409K**（values 按名合并 + grit + shared_with_webview；**content R shim = content∪ui**，含 `R$array`/`ui_com_google_android_gms_fonts_certs*`；见 §7、§12.11、§12.12）。此前 ~140K 残缺包与仅 styles 修好的 ~391K 包均已作废 |
| GitHub Release | https://github.com/hongqing1/chromiumsdk/releases/tag/v132.0.6834.165-arm64 |
| 重建 kit 分支 | https://github.com/hongqing1/chromiumsdk/tree/v132.0.6834.165-arm64（patches / gn / packaging / docs，无完整 Chromium 树） |
| 应用接入 | 第 9 节进行中；§12.11/§12.12 已解；**§12.13**：MI PAD 4 上 Vulkan GpuInit CHECK——须换 §12.13 后的主 AAR（res 不变） |

## 1. 版本

| 候选 | Android 8 | 补丁 | 结论 |
|------|-----------|------|------|
| `132.0.6834.165` | 支持 | 补丁动到的 67 个文件，`.86` 到 `.165` 一个都没变。`001`、`003` 在 `.165` 上 `git apply --check` 通过，`002` 只有 `Profile.java` 一处上下文对不上 | 这次用 |
| `138.0.7204.180` | 支持，是最后一版（2025-07-30） | 跨 6 个里程碑，`002` 这份 61KB 的胶水补丁要逐个文件重做 | 以后再说 |
| 139 及以上 | WebView 最低 Android 10 | — | 不能用 |

两条线都已经没有上游安全补丁。升到 `.165` 只是补上 132 分支 2025-01 中到 2025-02 初的修复，不改变「冻结内核、不能当上架内核」这个前提。

## 2. 环境和源码

编译机用 Linux（Ubuntu 22.04，WSL2 可以）。磁盘留 150GB 以上，内存 32GB。拉 Chromium 源码要走代理。

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

crwebview 先 fork 到内部 GitLab，后面的改动都提交在 fork 上，下次能原样重编。仓库整个放到 `src/android_webview/crwebview/`，`draw_functor.cc` 里的 include 写的就是这个路径：

```bash
git clone <内部 GitLab>/crwebview.git android_webview/crwebview
echo "android_webview/crwebview/" >> .git/info/exclude

git apply android_webview/crwebview/patches/001.android_webview.support_library.patch
git apply --reject android_webview/crwebview/patches/002.android_webview.glue.patch
git apply android_webview/crwebview/patches/003.android_webview.BUILD.gn.patch
```

`002` 会在 `glue/.../Profile.java` 留下一个 `.rej`。`132.0.6834.165` 的这个文件在 `NonNull` 前面多 import 了一个 `AnyThread`。手工把文件开头的五个 `android.webkit.*` import（`CookieManager`、`GeolocationPermissions`、`ServiceWorkerController`、`ValueCallback`、`WebStorage`）换成 `org.chromium.android_crwebview.webkit.*`，再删掉 `.rej`。除了这一处，其它文件打不上就停，说明这棵树不是 `132.0.6834.165`。

## 3. 补丁和仓库布局对齐

公开的 `002`、`003` 停在 2024-12-18 的布局：`MyDrawFunctor` 在 `com.android.webview.chromium`，native 放在 `android_webview/glue/java/src/draw_glue/`，`webkit_glue_java` 定义在 `android_webview/BUILD.gn`。2025-01-06 的提交 `fix draw_fn implements` 把它们挪进了仓库自己的 `BUILD.gn`。2.0.0 里 `MyDrawFunctor` 在 `org.chromium.android_crwebview.webkit`，用的是新布局，补丁没有跟着更新。按补丁原样编，`gn gen` 会报找不到 `glue/java/src/com/android/webview/chromium/MyDrawFunctor.java`。

统一按仓库布局，打完补丁后改这几处：

| 文件 | 补丁里写的 | 改成 |
|------|-----------|------|
| `android_webview/BUILD.gn` | `003` 新增的 `draw_fn_impl_jni_headers`、`draw_fn_impl_java`、`webkit_glue_java`、`webkit_glue_resources` | 整段删掉，用 `//android_webview/crwebview:` 下的同名目标 |
| `android_webview/BUILD.gn` 的 `libwebviewchromium_tmpl` | `sources` 是 `glue/java/src/draw_glue/*.cc`，`deps` 有 `":draw_fn_impl_jni_headers"` | `sources` 换成 `//android_webview/crwebview/java/src/draw_fn/` 下的 `overlays_manager.cc`、`allocator.cc`、`draw_functor.cc`，`deps` 换成 `"//android_webview/crwebview:draw_fn_impl_jni_headers"` |
| `android_webview/BUILD.gn` 的 `browser_java` | 多加了源文件 `java/src/org/chromium/android_crwebview/webkit/JavascriptInterface.java`，`deps` 有 `":webkit_glue_java"` | 删掉这行源文件。这个类已经在 `webkit_glue_java` 里，两处都编会重复。`deps` 换成 `"//android_webview/crwebview:webkit_glue_java"` |
| `android_webview/glue/BUILD.gn` | `"//android_webview:webkit_glue_java"` | `"//android_webview/crwebview:webkit_glue_java"` |
| `glue/.../WebViewChromiumAwInit.java` | 直接用 `MyDrawFunctor`，没有 import | 加 `import org.chromium.android_crwebview.webkit.MyDrawFunctor;` |
| `crwebview/BUILD.gn` 的 `webkit_glue_java` | `sources` 里也列了 `MyDrawFunctor.java` | 删掉这一行，只留在 `draw_fn_impl_java` |
| `crwebview/BUILD.gn` 的 `crwebkit_aar` | `output` 是 `android_crwebview_webkit.WebView-v2.0.0.aar` | 改成 `crwebview-132.0.6834.165.aar` |

改完 `gn gen` 不报重复定义、不报找不到目标，再往下做。`javac` 报找不到 `org.chromium.android_crwebview.webkit.*` 时，给报错的那个目标加 `//android_webview/crwebview:webkit_glue_java`。`webkit_glue_java` 不依赖 `browser_java`，不会成环。

## 4. 修 Android 8

| 现象 | 原因 | 改法 |
|------|------|------|
| Android 8、9、10 一创建就 `NoSuchMethodError` | `WebView.java` 构造函数直接调用 `getImportantForContentCapture()`，API 30 才有（issue #9） | 包上版本判断 |
| 没有 Vulkan 1.1 的机器一初始化就崩在 `CHECK` | `draw_functor.cc` 只有 `MyDrawFunctorVulkan`。`GetDrawFnFunctionTable` 不管参数，先建 Vulkan 实例和设备队列，失败就 `CHECK`。`init(true)` 也写死。Chromium 的 Vulkan 要 1.1，Android 8 机器最多 1.0 | 补回 GLES 实现，默认走 GLES |
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

### 4.2 GLES 绘制

132 树里 `android_webview/test/shell/src/draw_fn/context_manager.cc` 同时有 `ContextManagerGL` 和 `ContextManagerVulkan`，按 `use_vulkan` 二选一。crwebview 的 `draw_functor.cc` 就是从它改的，只留了 Vulkan 那一半。

1. 把 `ContextManagerGL` 整个类拷进 `crwebview/java/src/draw_fn/draw_functor.cc`，改名 `MyDrawFunctorGL`，基类换成 `DrawFunctor`。`InitializeGLBindings`、`GetConfig`、`DoCreateContext`、`DestroyContext`、`MakeCurrent` 原样带上。
2. `Draw` 里在 `draw_gl` 之前把表面清成透明。我们的表面下面没有别的内容，不清的话透明区域是上一帧残留：

```cpp
  MakeCurrent();
  glDisableFn(GL_SCISSOR_TEST);
  glClearColorFn(0, 0, 0, 0);
  glClearFn(GL_COLOR_BUFFER_BIT);
  AwDrawFn_DrawGLParams params{kAwDrawFnVersion};
```

`glDisableFn`、`glClearColorFn`、`glClearFn` 照 `glReadPixelsFn` 的写法，在 `InitializeGLBindings` 里用 `AssignProc` 取。

3. JNI 入口按参数分开，Vulkan 只在要用时才初始化：

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

4. `MyDrawFunctor.java` 两处 `true` 换成一个常量：

```java
private static final boolean USE_VULKAN = false;

public static long getDrawFnFunctionTable() {
    return MyDrawFunctorJni.get().getDrawFnFunctionTable(USE_VULKAN);
}

public MyDrawFunctor() {
    mMyDrawFunctor = MyDrawFunctorJni.get().init(USE_VULKAN);
}
```

所有版本都走 GLES，只维护一条绘制路径。Android 8、9 的系统界面本来就是 GL 渲染，上游测试壳默认也是 GL。Vulkan 的代码留着不删。Android 11 以上哪台机器 GLES 有问题，再按 `SDK_INT` 打开 Vulkan。

**注意（§12.13）：** 仅改 Java `USE_VULKAN` / `SetDrawFnUseVulkan` 不够——`allocator.cc` 的 `QueryRenderMode()` 必须按 `g_use_vulkan` 返回（默认 GLES），否则 `AwDrawFnImpl::IsUsingVulkan()` 仍为 true，GpuInit 会 `CHECK` Vulkan。

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

写到 `src/out/crwebview_arm64/args.gn`：

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

`proprietary_codecs` 和 `ffmpeg_branding` 必须一起开，否则课件里的 H.264、AAC 没有画面。`is_official_build` 先关，不做 LTO。不填任何 Google API key。

```bash
gn gen out/crwebview_arm64
gn ls out/crwebview_arm64 | grep -E 'crwebview|autofill.*resources|media.*resources'
autoninja -C out/crwebview_arm64 \
  //android_webview/crwebview:crwebkit_aar \
  //android_webview/crwebview:webkit_glue_resources \
  //android_webview:crwebview_ui_android_resources \
  //android_webview:crwebview_content_resources \
  //android_webview:crwebview_embedder_support_resources \
  //android_webview:resources
```

`gn ls` 里查到的 autofill、media 资源目标也加进 `autoninja`。链接时内存不够，在 `args.gn` 加 `concurrent_links = 1` 再 `gn gen`。不要编 `system_webview_apk`、Trichrome，也不要 `autoninja` 不带目标。

### 资源 AAR

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
| `src/main/res` | 七个资源目标在 `out/crwebview_arm64/gen/` 下产出的 res **按资源名合并**合在一起（见下「合并 values，勿覆盖」）。报 `Duplicate resources` 时，两份内容一样就删一份；内容不一样就停，先查是哪两个目标。不要对同路径 `values/*.xml` 做 last-write-wins 拷贝 |
| `src/main/java` | 下面脚本生成的七个 `R.java` |

### 合并 values，勿覆盖（packaging）

七个资源目标的 `values/styles.xml`、`values/dimens.xml` 等**相对路径同名**。若打包脚本对 `res/` 做简单 `cp` / last-write-wins，后拷的包会整文件盖掉先拷的包。实编里 `android_webview` 的几乎空 `WebViewBaseTheme` 盖掉了 `ui` 的完整 styles，应用侧 `process*Resources` 随即失败（见 §12.11）。

正确做法：

1. 用 `packaging/merge_res_from_sources.py`：同路径 values XML **按资源名合并**（同名同内容保留一份；同名异内容要停下来查）；非 values 文件仍按路径拷贝。
2. 一并拉入 `components/browser_ui/.../shared_with_webview` 的 dimens（如 `chip_icon_size`），以及 layout 引用的 grit 字符串 zip（`crwebview_*_strings_grd.resources.zip`）。
3. 收尾走更新后的 `packaging/package_res_aar_finish.sh`（可 `aapt2 link`；缺宿主 AppCompat 属性时回退合成非 final 的 NS `R`）。AppCompat stub **不进** AAR。
4. **不要**对缺失 style 做 whack-a-mole 空壳补丁；完整 res AAR 约 **409K**（含 content∪ui R shim；残缺 last-write-wins ~140K 与仅 styles 修好的 ~391K 均已作废，见 §12.11 / §12.12）。

重建 kit：https://github.com/hongqing1/chromiumsdk/tree/v132.0.6834.165-arm64 `packaging/`。

转发类按七个资源目标的 `R.txt` 生成。`R.txt` 在 `out/crwebview_arm64/gen/` 下，用 `find out/crwebview_arm64/gen -name '*R.txt'` 找到这七个目标对应的那份：

```python
#!/usr/bin/env python3
# 用法：gen_r_shims.py <输出目录> <包名>=<R.txt>[+<R.txt>...] ...
# content 须 content∪ui（Chromium content_java 传递合并），否则缺 R$array / fonts_certs
import os
import sys
from collections import defaultdict

NS = 'org.chromium.crwebview.res'

out = sys.argv[1]
for arg in sys.argv[2:]:
    pkg, rtxt = arg.split('=', 1)
    types = defaultdict(list)
    with open(rtxt) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 3:
                types[parts[1]].append((parts[0], parts[2]))
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


**content → ui：** Chromium 的 `content_java` 把 ui 资源合并进 `org.chromium.content.R`。shim 必须对 content 传 `CONTENT_RTXT+UI_RTXT`（见 §12.12），否则运行时缺 `R$array`（`ui_com_google_android_gms_fonts_certs*`）。
`kind` 是 `int` 或 `int[]`，`styleable` 的数组和下标一起转发（`org.chromium.ui` 用到了 `R$styleable`）。字段不加 `final`，`R` 的值要等应用打包时才定。转发类引用了合并 res 里没有的名字时，`compileReleaseJavaWithJavac` 会报错，说明 res 少拷了一份。

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

主 AAR 不并进来。它是 GN 的直接产物，222MB，并进来就要每次重打 so 和 assets，`md5` 也对不上 GN 出的那份。最后放进应用的是两个文件。

## 8. 核对

| 项 | 怎么看 |
|----|--------|
| 内核版本 | `classes.jar` 里能搜到 `132.0.6834.165`，搜不到 `132.0.6834.86` |
| ABI | AAR 的 `jni/` 里只有 `arm64-v8a` |
| 布局 | 有 `org/chromium/android_crwebview/webkit/WebView.class`、`MyDrawFunctor.class`；没有 `com/android/webview/chromium/MyDrawFunctor.class` |
| GLES | `javap -c` 看 `MyDrawFunctor.class`，`init`、`getDrawFnFunctionTable` 传的是 `false`（`iconst_0`）。另确认 `QueryRenderMode` 读 `g_use_vulkan`（§12.13），勿再写死 VULKAN。Android 8 真机 logcat 里没有 `Failed to create Vulkan` / `gpu_init.cc Check failed` |
| 重定位 | `llvm-readelf -d libwebviewchromium.so` 里没有 `RELR`、`ANDROID_RELR` |
| assets | `icudtl.dat`、`resources.pak`、`chrome_100_percent.pak`、`snapshot_blob_64.bin`、`stored-locales/`（本树 **无** `v8_context_snapshot_64.bin`，核对时勿当失败） |
| 资源 AAR | 只有一个 `crwebview-res-132.0.6834.165.aar`（完整包约 **391K**，勿用旧 ~140K）。清单 `package` 是 `org.chromium.crwebview.res`。`classes.jar` 里有第 7 节列出的每个包名的 `R` 转发类，主 AAR 里没有任何 `R.class`。AAR 内 `values/styles.xml` 须含 ui 侧完整 theme（不止 `WebViewBaseTheme`） |
| 日志 | `classes.jar` 里搜不到 `drawWebViewFunctor STEP` |

## 9. 换进应用

接入在 `crwebview` 分支，`WebViewWrapper`、实验室开关、JSB 反射都不改。

**进度（2026-10-30）：** 第 9 节接入进行中。§12.11/§12.12 已解。真机（MI PAD 4）又因 §12.13 `QueryRenderMode` 写死 Vulkan 崩在 GpuInit；主 AAR 已按 GLES 重编并 `--clobber` 上传（res 未动）。换 **主 AAR** 后再测。


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

### 12.11 资源 AAR：`values/styles.xml` last-write-wins（接入 `process*Resources` 失败）

| 项 | 内容 |
|----|------|
| 现象 | 主 AAR 已就绪、残缺 res AAR（约 140K）接入应用后，`:app:process*Resources` / 资源链接失败；缺大量 style / dimens / string。AAR 里 `values/styles.xml` 几乎只有空的 `WebViewBaseTheme` |
| 原因 | 七个资源目标的 `values/*.xml` **相对路径同名**。打包若按路径后写覆盖，后拷的 `android_webview` 几乎空 `WebViewBaseTheme` 会盖掉先拷的 `ui` 完整 styles。layout 还依赖 grit 字符串 zip 与 `shared_with_webview` dimens，简单拷 gen res 也会漏 |
| 改法 | **按资源名合并**，不要 stub style 打地鼠。用 `packaging/merge_res_from_sources.py` + 更新后的 `package_res_aar_finish.sh`（见 §7「合并 values，勿覆盖」）；补上 grit string zips 与 `shared_with_webview` dimens。完整 res AAR 约 **391K**，已重新上传到 [v132.0.6834.165-arm64](https://github.com/hongqing1/chromiumsdk/releases/tag/v132.0.6834.165-arm64)；packaging 修法在 kit 分支 commit `e1dcc89` |
| 不要 | 对报错 style 名逐个写空 `<style>` 糊过去；不要继续分发 ~140K 的残缺 res AAR |

### 12.12 资源 AAR：`content.R` 未合并 ui → `NoClassDefFoundError: R$array`（运行时字体查找）

| 项 | 内容 |
|----|------|
| 现象 | 完整 res AAR（§12.11）接入后，进页 / 字体路径崩溃：`NoClassDefFoundError: Lorg/chromium/content/R$array;`，栈在 `AndroidFontLookupImpl.tryFetchFont`（`import org.chromium.content.R`；读 `R.array.ui_com_google_android_gms_fonts_certs`） |
| 原因 | `ui_com_google_android_gms_fonts_certs*` 定义在 **ui** 资源（`ui/android/java/res/values/font_certs.xml`），出现在 ui 的 R.txt。Chromium 的 `content_java` 会把传递依赖的 ui 资源合并进 **content.R**；我们的 shim 若只按 content 自己的 R.txt 生成，jar 里只有 `org/chromium/ui/R$array`，没有 `org/chromium/content/R$array` |
| 改法 | `gen_r_shims.py` 支持 `pkg=R.txt+R.txt` 并集；`package_res_aar_finish.sh` 对 **content** 传 `CONTENT_RTXT+UI_RTXT`（ui 包仍单独一份）。NS `org.chromium.crwebview.res.R` 仍来自七份 R.txt 并集，本就有这些 array。重建后 `jar tf` 应有 `org/chromium/content/R$array.class`，`javap` 可见三个 `ui_com_google_android_gms_fonts_certs*`。完整 res AAR 约 **409K**，已 `--clobber` 上传到 [v132.0.6834.165-arm64](https://github.com/hongqing1/chromiumsdk/releases/tag/v132.0.6834.165-arm64) |
| 不要 | 只在应用侧改 `import` / 反射绕开；不要只补空的 `R$array` 而不合并 ui R.txt（下次还有别的 ui 字段会再炸）。其它跨包 R 引用可再扫，但 content→ui 是已知崩溃点 |

### 12.13 `QueryRenderMode` 写死 Vulkan → GpuInit `CHECK`（MI PAD 4 / API 27）

| 项 | 内容 |
|----|------|
| 现象 | 换上 ~409K res 后 `R$array` 已好，真机（MI PAD 4，API 27）仍崩：`Failed to create Vulkan` → `FATAL:gpu_init.cc Check failed: result`。logcat 同时有 `egl-display-type=angle:OpenGLES` |
| 原因 | Java `MyDrawFunctor.USE_VULKAN=false` 且 JNI `SetDrawFnUseVulkan(false)` 已生效，但 crwebview `allocator.cc` 的 `QueryRenderMode()` **写死** `AW_DRAW_FN_RENDER_MODE_VULKAN`，忽略 `g_use_vulkan`。`AwDrawFnImpl::IsUsingVulkan()` 仍为 true → `aw_main_delegate` 追加 `kWebViewDrawFunctorUsesVulkan` → `GpuInit::InitializeInProcess` 调 `InitializeVulkan()` 且 `CHECK` 无回退。上游 test shell 则是 `return g_use_vulkan ? VULKAN : OPENGL_ES`，默认 `g_use_vulkan=false` |
| 改法 | 与 test shell 对齐：`g_use_vulkan = false`；`QueryRenderMode()` 按 flag 返回。补丁 `patches/crwebview/0026-allocator-query-render-mode-gles.patch`。增量 `ninja -C out/crwebview_arm64 -j6 android_webview/crwebview:crwebkit_aar`（PATH 含 `bin/` + PY3_PROTO）；资产注入后主 AAR ~104M，已 `--clobber` 上传到 [v132.0.6834.165-arm64](https://github.com/hongqing1/chromiumsdk/releases/tag/v132.0.6834.165-arm64)（**未**动 res AAR） |
| 核对 | `javap -c MyDrawFunctor` 仍为 `iconst_0`；`llvm-objdump -d allocator.o` 中 `QueryRenderMode` 为 `ldrb w0, [g_use_vulkan]`（不再是常量 VULKAN）。期望：flag false 时回报 GLES，不再走 Vulkan GpuInit |
| 不要 | 只改 Java 默认而不改 `QueryRenderMode`；不要为躲 CHECK 去关整棵 GPU 进程（应让 draw-fn 模式与 GLES 路径一致） |

