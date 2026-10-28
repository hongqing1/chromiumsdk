#!/usr/bin/env bash
set -u
ROOT=/workspace/chromium-src-aar
LOG=$ROOT/logs/09-build.log
AAR=$ROOT/artifacts/chromium_webview.aar
POLL=$ROOT/logs/12-poll.log
RESULT=$ROOT/logs/POLL_RESULT.txt
mkdir -p "$ROOT/artifacts" "$ROOT/logs"
echo "watch start $(date -Iseconds)" | tee -a "$POLL"
while true; do
  if [ -f "$AAR" ] && [ -s "$AAR" ]; then
    echo "AAR_FOUND $(date -Iseconds) $(ls -lh "$AAR")" | tee -a "$POLL"
    echo AAR_FOUND > "$RESULT"
    # write ARTIFACTS.md
    cat > "$ROOT/artifacts/ARTIFACTS.md" <<AEOF
# Chromium embed AAR

- file: chromium_webview.aar
- size: $(ls -lh "$AAR" | awk '{print $5}')
- built: $(date -Iseconds)
- rev: 133.0.6943.123
- target: android_webview/embed_aar:chromium_webview
- out: out/AarArm64
AEOF
    # update STATUS
    cat > "$ROOT/STATUS.md" <<SEOF
# Chromium embed AAR — DONE

- aar: $AAR
- time: $(date -Iseconds)
SEOF
    break
  fi
  NP=$(pgrep -f '/third_party/ninja/ninja -C out/AarArm64' | head -1 || true)
  prog=$(rg -o '\[[0-9]+/[0-9]+\]' "$LOG" | tail -1 || echo '?')
  avail=$(($(df -Pk / | awk 'NR==2{print $4}')/1024/1024))
  echo "$(date '+%F %T %Z') ninja=${NP:-none} $prog disk=${avail}GB" | tee -a "$POLL"
  if [ -z "${NP:-}" ]; then
    sleep 60
    if [ -f "$AAR" ] && [ -s "$AAR" ]; then
      continue
    fi
    # check if build finished with error
    if rg -q 'BUILD_EXIT:' "$LOG"; then
      exitcode=$(rg -o 'BUILD_EXIT:[0-9]+' "$LOG" | tail -1)
      echo "NINJA_DONE $exitcode $(date -Iseconds)" | tee -a "$POLL"
      if echo "$exitcode" | rg -q 'BUILD_EXIT:0'; then
        # maybe aar elsewhere
        find "$ROOT/src/out/AarArm64" -name '*.aar' 2>/dev/null | tee -a "$POLL"
        found=$(find "$ROOT/src/out/AarArm64" -name 'chromium_webview.aar' 2>/dev/null | head -1)
        if [ -n "$found" ]; then
          cp -f "$found" "$AAR"
          continue
        fi
      fi
      echo NINJA_DEAD_NO_AAR > "$RESULT"
      rg -n 'FAILED:|error:|BUILD_EXIT|ninja: build stopped' "$LOG" | tail -40 >> "$POLL"
      cat > "$ROOT/STATUS.md" <<SEOF
# Chromium embed AAR — FAILED

- $exitcode
- see logs/09-build.log and logs/12-poll.log
- time: $(date -Iseconds)
SEOF
      break
    fi
    # ninja gone but no BUILD_EXIT yet — wait a bit more then declare dead
    sleep 120
    NP2=$(pgrep -f '/third_party/ninja/ninja -C out/AarArm64' | head -1 || true)
    if [ -z "${NP2:-}" ] && [ ! -f "$AAR" ]; then
      echo NINJA_DEAD_NO_AAR > "$RESULT"
      echo "NINJA_DEAD_NO_AAR $(date -Iseconds)" | tee -a "$POLL"
      break
    fi
  fi
  if [ "$avail" -lt 15 ]; then
    echo DISK_LOW > "$RESULT"
    echo "DISK_LOW $(date -Iseconds)" | tee -a "$POLL"
    break
  fi
  sleep 180
done
cat "$RESULT" 2>/dev/null || true
