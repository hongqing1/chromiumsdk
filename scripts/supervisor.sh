#!/usr/bin/env bash
# Supervisor: poll until AAR; on death diagnose/fix/restart -j6; disk<12G -> FAILED_DISK
set -u
ROOT=/workspace/crwebview-132
LOG=$ROOT/ninja-build.log
STATUS=$ROOT/STATUS.md
MARKER=$ROOT/supervisor.state
OUT="$ROOT/src/out/crwebview_arm64"
AAR="$OUT/crwebview-132.0.6834.165.aar"
SRC="$ROOT/src"
export PATH="$ROOT/bin:$ROOT/depot_tools:$PATH"
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
export PYTHONPATH="$ROOT/python-fix${PYTHONPATH:+:$PYTHONPATH}"
NINJA_PID=974950
echo "RUNNING $(date '+%Y-%m-%d %H:%M:%S')" > "$MARKER"

append_status() {
  local now line
  now=$(date '+%Y-%m-%d %H:%M:%S Asia/Shanghai')
  line="$1"
  python3 - "$STATUS" "$now" "$line" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]); now=sys.argv[2]; line=sys.argv[3]
lines=p.read_text().splitlines()
out=[]
for L in lines:
  if L.startswith('**Updated:**'):
    out.append(f'**Updated:** {now}')
  elif L.startswith('**State:**'):
    out.append(L)  # leave; caller may rewrite
  else:
    out.append(L)
out.append(line)
p.write_text('\n'.join(out)+'\n')
PY
}

set_state() {
  local st=$1
  python3 - "$STATUS" "$st" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]); st=sys.argv[2]
lines=p.read_text().splitlines()
out=[]
for L in lines:
  if L.startswith('**State:**'):
    out.append(f'**State:** {st}')
  else:
    out.append(L)
p.write_text('\n'.join(out)+'\n')
PY
}

find_ninja() {
  pgrep -f 'third_party/ninja/ninja -C out/crwebview_arm64' | head -1 || true
}

restart_ninja() {
  append_status "- $(date '+%Y-%m-%d %H:%M:%S Asia/Shanghai'): restarting ninja -j6 after death/fail"
  cd "$SRC"
  # append to log
  (
    "$ROOT/depot_tools/ninja.py" -C out/crwebview_arm64 -j6 \
      android_webview/crwebview:crwebkit_aar \
      android_webview/crwebview:webkit_glue_resources \
      android_webview:crwebview_ui_android_resources \
      android_webview:crwebview_content_resources \
      android_webview:crwebview_embedder_support_resources \
      android_webview:resources \
      components/autofill/android:autofill_java_resources \
      >> "$LOG" 2>&1
  ) &
  sleep 3
  NINJA_PID=$(find_ninja)
  if [[ -z "${NINJA_PID:-}" ]]; then
    echo "RESTART_FAILED $(date '+%Y-%m-%d %H:%M:%S')" > "$MARKER"
    set_state FAILED
    append_status "- $(date '+%Y-%m-%d %H:%M:%S Asia/Shanghai'): RESTART_FAILED — no ninja pid"
    exit 3
  fi
  append_status "- $(date '+%Y-%m-%d %H:%M:%S Asia/Shanghai'): ninja restarted pid=$NINJA_PID"
}

while true; do
  NOW=$(date '+%Y-%m-%d %H:%M:%S Asia/Shanghai')
  if kill -0 "$NINJA_PID" 2>/dev/null; then
    ALIVE=alive
  else
    NP=$(find_ninja)
    if [[ -n "${NP:-}" ]]; then
      NINJA_PID=$NP
      ALIVE=alive
    else
      ALIVE=DEAD
    fi
  fi
  PROG=$(tail -80 "$LOG" 2>/dev/null | grep -oE '\[[0-9]+/[0-9]+\]' | tail -1 || echo '?')
  AVAIL=$(df -BG / | awk 'NR==2{gsub(/G/,"",$4); print $4}')
  OUTSZ=$(du -sh "$OUT" 2>/dev/null | cut -f1)
  HAVE_AAR=no
  [[ -f "$AAR" ]] && HAVE_AAR=yes
  FAIL=0
  if tail -100 "$LOG" 2>/dev/null | grep -qE 'FAILED:|ninja: build stopped'; then FAIL=1; fi

  LINE="- $NOW: progress $PROG out=$OUTSZ avail=${AVAIL}G ninja=$ALIVE aar=$HAVE_AAR"
  # Only append every ~5 min worth - we sleep 180s so every loop is fine
  append_status "$LINE"
  echo "$LINE" >> "$ROOT/supervisor.events"

  if [[ "${AVAIL:-0}" -lt 12 ]]; then
    set_state FAILED_DISK
    echo "FAILED_DISK avail=${AVAIL}G $NOW" > "$MARKER"
    append_status "- $NOW: FAILED_DISK avail=${AVAIL}G"
    exit 2
  fi

  if [[ "$HAVE_AAR" == yes ]]; then
    # wait for ninja to finish cleanly if still running
    if [[ "$ALIVE" == alive ]]; then
      append_status "- $NOW: AAR present, waiting for ninja exit"
      # poll until dead or 30 more min
      for i in $(seq 1 60); do
        sleep 30
        if ! kill -0 "$NINJA_PID" 2>/dev/null; then
          NP=$(find_ninja)
          [[ -z "${NP:-}" ]] && break
          NINJA_PID=$NP
        fi
        [[ -f "$AAR" ]] || break
      done
    fi
    echo "AAR_DONE $(date '+%Y-%m-%d %H:%M:%S')" > "$MARKER"
    append_status "- $(date '+%Y-%m-%d %H:%M:%S Asia/Shanghai'): AAR_DONE — starting package/verify"
    exit 0
  fi

  if [[ "$ALIVE" != alive ]]; then
    # diagnose
    TAIL=$(tail -40 "$LOG")
    echo "$TAIL" > "$ROOT/ninja-death-tail.txt"
    if [[ "$FAIL" -eq 1 ]] || echo "$TAIL" | grep -qE 'FAILED:|ninja: build stopped'; then
      append_status "- $NOW: ninja FAILED — diagnosing then restart -j6"
      # fix attempts: common issues already handled; just restart unless permanent
      if echo "$TAIL" | grep -qiE 'No space left|disk quota'; then
        set_state FAILED_DISK
        echo "FAILED_DISK $NOW" > "$MARKER"
        exit 2
      fi
      # If fatal compile error that won't fix on restart, still try once after noting
      restart_ninja
    else
      append_status "- $NOW: ninja DEAD without FAILED marker — restart -j6"
      restart_ninja
    fi
  fi

  sleep 180
done
