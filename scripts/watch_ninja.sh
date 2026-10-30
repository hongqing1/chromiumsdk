#!/usr/bin/env bash
# Background watcher: update STATUS.md every 5 min until ninja done or dead
set -u
ROOT=/workspace/crwebview-132
LOG=$ROOT/ninja-build.log
STATUS=$ROOT/STATUS.md
NINJA_PID=1294171
MARKER=$ROOT/watch_ninja.state
echo "RUNNING $(date '+%Y-%m-%d %H:%M:%S')" > "$MARKER"
while true; do
  NOW=$(date '+%Y-%m-%d %H:%M:%S Asia/Shanghai')
  if kill -0 "$NINJA_PID" 2>/dev/null; then
    ALIVE=alive
  else
    # maybe respawned
    NP=$(pgrep -f 'third_party/ninja/ninja -C out/crwebview_arm64' | head -1 || true)
    if [[ -n "${NP:-}" ]]; then
      NINJA_PID=$NP
      ALIVE=alive
    else
      ALIVE=DEAD
    fi
  fi
  PROG=$(tail -50 "$LOG" 2>/dev/null | grep -oE '\[[0-9]+/[0-9]+\]' | tail -1 || echo '?')
  AVAIL=$(df -BG / | awk 'NR==2{gsub(/G/,"",$4); print $4}')
  OUTSZ=$(du -sh "$ROOT/src/out/crwebview_arm64" 2>/dev/null | cut -f1)
  AAR=no
  if ls "$ROOT/src/out/crwebview_arm64"/crwebview-132.0.6834.165.aar >/dev/null 2>&1; then AAR=yes; fi
  # FAILED in last 80 lines?
  FAIL=0
  if tail -80 "$LOG" 2>/dev/null | grep -qE 'FAILED:|ninja: build stopped'; then FAIL=1; fi
  LINE="- $NOW: progress $PROG out=$OUTSZ avail=${AVAIL}G ninja=$ALIVE aar=$AAR"
  # update Updated: and append
  python3 - "$STATUS" "$NOW" "$LINE" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]); now=sys.argv[2]; line=sys.argv[3]
lines=p.read_text().splitlines()
out=[]
for L in lines:
  if L.startswith('**Updated:**'):
    out.append(f'**Updated:** {now}')
  else:
    out.append(L)
out.append(line)
p.write_text('\n'.join(out)+'\n')
PY
  echo "$LINE" >> "$ROOT/watch_ninja.events"
  if [[ "$AVAIL" -lt 12 ]]; then
    echo "FAILED_DISK avail=${AVAIL}G" > "$MARKER"
    exit 2
  fi
  if [[ "$AAR" == yes ]]; then
    echo "AAR_DONE $NOW" > "$MARKER"
    exit 0
  fi
  if [[ "$ALIVE" != alive ]]; then
    if [[ "$FAIL" -eq 1 ]]; then
      echo "NINJA_FAILED $NOW" > "$MARKER"
    else
      # check exit via log footer
      if tail -5 "$LOG" | grep -q 'ninja: build stopped'; then
        echo "NINJA_FAILED $NOW" > "$MARKER"
      elif tail -5 "$LOG" | grep -qE '^\[.*\]$|still waiting'; then
        echo "NINJA_DEAD $NOW" > "$MARKER"
      else
        # maybe clean success without aar yet? unlikely
        echo "NINJA_DEAD $NOW" > "$MARKER"
      fi
    fi
    exit 1
  fi
  sleep 300
done
