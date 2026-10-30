# Packaging scripts (res AAR + verify)

Used after ninja finishes the main `crwebkit_aar` and resource targets.

- `package_res_aar.sh` / `package_res_aar_finish.sh` — build `crwebview-res-*.aar` (R-shims + merged res) without Gradle
- `merge_res_from_sources.py` — merge the 7 targets' `.res.sources` into one `res/` tree.
  **Important:** values XML with the same relative path (e.g. `values/styles.xml`) are
  merged by resource name, not overwritten. The old last-write-wins copy left only
  `WebViewBaseTheme` and broke app resource linking.
  Also pulls:
  - `components/browser_ui/.../shared_with_webview` dimens (`chip_icon_size`, …)
  - grit string zips referenced by layouts (`crwebview_*_strings_grd.resources.zip`)
- `gen_r_shims.py` — generate R.java shims from R.txt maps
- `verify_aars.sh` — sanity-check main + res AARs
- `r_txt_list.txt` — example R.txt path map from the 132 build (paths under `out/crwebview_arm64/gen/`)

Scripts currently assume tree root `/workspace/crwebview-132` and out dir `src/out/crwebview_arm64`. Edit `ROOT`/`OUT` at the top when rebuilding elsewhere.

`package_res_aar_finish.sh` tries `aapt2 link` (with a temporary AppCompat theme stub) to
produce `org.chromium.crwebview.res.R`; if link still fails on AppCompat attrs the host
app provides, it falls back to a synthetic non-final NS R from the seven R.txt files.
The AppCompat stub is **not** shipped in the AAR.

Do not commit `_build/`, `_repack_main/`, `_verify/`, or unpacked AAR intermediates.
