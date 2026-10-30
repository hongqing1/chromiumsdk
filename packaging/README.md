# Packaging scripts (res AAR + verify)

Used after ninja finishes the main `crwebkit_aar` and resource targets.

- `package_res_aar.sh` / `package_res_aar_finish.sh` — build `crwebview-res-*.aar` (R-shims + merged res) without Gradle
- `gen_r_shims.py` — generate R.java shims from R.txt maps
- `verify_aars.sh` — sanity-check main + res AARs
- `r_txt_list.txt` — example R.txt path map from the 132 build (paths under `out/crwebview_arm64/gen/`)

Scripts currently assume tree root `/workspace/crwebview-132` and out dir `src/out/crwebview_arm64`. Edit `ROOT`/`OUT` at the top when rebuilding elsewhere.

Do not commit `_build/`, `_repack_main/`, `_verify/`, or unpacked AAR intermediates.
