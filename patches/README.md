# Patches for Chromium 132.0.6834.165 + crwebview 88f8fc85

Apply order:

## 1. Stock crwebview patches (from `wuruxu/crwebview` @ 88f8fc85, also copied under `stock/`)

From Chromium `src/`:

```bash
git apply --reject android_webview/crwebview/patches/001.android_webview.support_library.patch
git apply --reject android_webview/crwebview/patches/002.android_webview.glue.patch
git apply --reject android_webview/crwebview/patches/003.android_webview.BUILD.gn.patch
```

If `002` leaves `Profile.java.rej` (AnyThread import context), apply:

```bash
git apply patches/chromium/0009-profile-java-import-fix.patch
# or manually swap the five android.webkit.* imports — see docs/BUILD_PITFALLS.md §12.1
rm -f android_webview/glue/java/src/com/android/webview/chromium/Profile.java.rej
```

(`patch -p1` with fuzz may apply 002’s Profile hunk without a .rej; either path is fine.)

## 2. This kit’s Chromium-tree patches (`patches/chromium/`, from `src/`)

```bash
git apply patches/chromium/0010-layout-realign-android_webview-BUILD.gn.patch
git apply patches/chromium/0011-glue-webkit-glue-java-path.patch
git apply patches/chromium/0012-color-data-fallthrough.patch
git apply patches/chromium/0013-data-directory-suffix.patch
git apply patches/chromium/0014-awinit-mydrawfunctor-import.patch
```

## 3. This kit’s crwebview-tree patches (`patches/crwebview/`, from `src/android_webview/crwebview/`)

```bash
cd android_webview/crwebview
git checkout --detach 88f8fc851879853f51cc02928e95db57fe99fb0a   # if not already
git apply /path/to/kit/patches/crwebview/0020-crwebview-BUILD.gn-aar-name.patch
git apply /path/to/kit/patches/crwebview/0021-android8-textureview-webview.patch
git apply /path/to/kit/patches/crwebview/0022-gles-scoped-allow-blocking-draw-functor.patch
git apply /path/to/kit/patches/crwebview/0023-mydrawfunctor-gles-default.patch
git apply /path/to/kit/patches/crwebview/0024-webview-delegate-wrapper.patch
git apply /path/to/kit/patches/crwebview/0025-buildconfig.patch
```

Do **not** re-apply stock 001/002/003 after the layout-realign patches.
