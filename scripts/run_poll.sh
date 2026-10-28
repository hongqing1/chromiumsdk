#!/usr/bin/env bash
set -u
LOG=/workspace/chromium-src-aar/logs/12-poll.log
AAR=/workspace/chromium-src-aar/artifacts/chromium_webview.aar
RESULT=/workspace/chromium-src-aar/logs/POLL_RESULT.txt
OBJ=/workspace/chromium-src-aar/src/out/AarArm64/obj/third_party/blink/renderer/platform/platform/color_data.o
STATUS=/workspace/chromium-src-aar/STATUS.md
echo "poll2 start $(date '+%F %T %Z')" | tee -a "$LOG"
while true; do
  if [ -f "$AAR" ]; then
    echo "AAR_FOUND $(date '+%F %T %Z') $(ls -lh "$AAR")" | tee -a "$LOG"
    echo AAR_FOUND > "$RESULT"
    exit 0
  fi
  NP=$(pgrep -f '/third_party/ninja/ninja -C out/AarArm64' | head -1 || true)
  if [ -z "$NP" ]; then
    sleep 60
    if [ -f "$AAR" ]; then
      echo AAR_FOUND > "$RESULT"
      echo "AAR_FOUND_AFTER_EXIT $(date '+%F %T %Z')" | tee -a "$LOG"
      exit 0
    fi
    echo "NINJA_DEAD_NO_AAR $(date '+%F %T %Z')" | tee -a "$LOG"
    rg -n 'FAILED:|error:|BUILD_EXIT|ninja: build stopped|fallthrough' /workspace/chromium-src-aar/logs/09-build.log | tail -40 >> "$LOG"
    echo NINJA_DEAD_NO_AAR > "$RESULT"
    exit 1
  fi
  prog=$(rg -o '\[[0-9]+/[0-9]+\]' /workspace/chromium-src-aar/logs/09-build.log | tail -1 || true)
  cur=$(echo "$prog" | tr -d '[]' | cut -d/ -f1)
  tot=$(echo "$prog" | tr -d '[]' | cut -d/ -f2)
  pct=$(python3 -c "print(f'{$cur/$tot*100:.1f}')" 2>/dev/null || echo '?')
  avail=$(($(df -Pk / | awk 'NR==2{print $4}')/1024/1024))
  cdo=missing; [ -f "$OBJ" ] && cdo=ok
  # detect fallthrough regression after last RESTART_FIXED
  LAST=$(rg -n 'RESTART_FIXED' /workspace/chromium-src-aar/logs/09-build.log | tail -1 | cut -d: -f1)
  if [ -n "$LAST" ] && tail -n +"$((LAST+1))" /workspace/chromium-src-aar/logs/09-build.log | rg -q 'fallthrough annotation does not directly precede'; then
    echo "FALLTHROUGH_AGAIN $(date '+%F %T %Z')" | tee -a "$LOG"
    echo FALLTHROUGH_AGAIN > "$RESULT"
    exit 2
  fi
  echo "$(date '+%F %T %Z') running $prog (~${pct}%) color_data.o=$cdo disk=${avail}GB ninja=$NP" | tee -a "$LOG"
  NOW=$(date '+%Y-%m-%d %H:%M:%S %Z')
  WP=$(pgrep -f 'watch_and_finish.sh' | head -1 || echo none)
  printf '%s\n' \
"# Chromium embeddable WebView AAR — STATUS" \
"" \
"Updated: ${NOW} (Asia/Shanghai)" \
"" \
"## State: RUNNING (~${pct}%)" \
"" \
"- **Chromium rev:** \`133.0.6943.123\`" \
"- **Ninja PID:** ${NP} (do not kill)" \
"- **Watcher:** PID ${WP} (do not kill)" \
"- **Progress:** ${prog}" \
"- **color_data.o:** ${cdo}" \
"- **gperf.py:** patched for gperf 3.2 (do not revert)" \
"- **Artifact yet:** no" \
"- **Disk free:** ~${avail}GB" \
"- **Log:** \`logs/09-build.log\`" \
> "$STATUS"
  if [ "$avail" -lt 15 ]; then
    echo DISK_LOW > "$RESULT"
    exit 3
  fi
  sleep 180
done
