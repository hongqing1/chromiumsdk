#!/usr/bin/env bash
# Wait for main AAR (or ninja death), then copy artifacts and update STATUS.
set -u
ROOT=/workspace/crwebview-132
OUT=$ROOT/src/out/crwebview_arm64
AAR_NAME=crwebview-132.0.6834.165.aar
MARKER=$ROOT/watch_ninja.state
ART=$ROOT/artifacts
STATUS=$ROOT/STATUS.md
LOG=$ROOT/finish_when_aar.log
exec >>"$LOG" 2>&1
echo "START $(date '+%F %T Asia/Shanghai')"
mkdir -p "$ART"
while true; do
  if [[ -f "$OUT/$AAR_NAME" ]]; then
    echo "FOUND AAR $(date '+%F %T')"
    break
  fi
  if [[ -f "$MARKER" ]] && grep -qE 'NINJA_FAILED|FAILED_DISK|NINJA_DEAD' "$MARKER"; then
    echo "STOP marker=$(cat "$MARKER")"
    # rewrite STATUS state
    python3 - <<PY
from pathlib import Path
p=Path("$STATUS"); t=p.read_text(); lines=[]
for L in t.splitlines():
  if L.startswith("**State:**"): lines.append("**State:** FAILED")
  else: lines.append(L)
lines.append(f"- finish_when_aar: stopped on marker $(open('$MARKER').read().strip())")
p.write_text("\n".join(lines)+"\n")
PY
    exit 1
  fi
  # ninja gone and no aar
  if ! pgrep -f 'third_party/ninja/ninja -C out/crwebview_arm64' >/dev/null; then
    sleep 30
    if [[ -f "$OUT/$AAR_NAME" ]]; then break; fi
    if ! pgrep -f 'third_party/ninja/ninja -C out/crwebview_arm64' >/dev/null; then
      echo "NINJA GONE without AAR $(date '+%F %T')"
      python3 - <<'PY'
from pathlib import Path
p=Path("/workspace/crwebview-132/STATUS.md")
lines=[]
for L in p.read_text().splitlines():
  if L.startswith("**State:**"): lines.append("**State:** FAILED")
  else: lines.append(L)
lines.append("- finish_when_aar: ninja gone, no AAR")
p.write_text("\n".join(lines)+"\n")
PY
      exit 1
    fi
  fi
  sleep 120
done
cp -f "$OUT/$AAR_NAME" "$ART/"
SZ=$(stat -c%s "$ART/$AAR_NAME")
NOW=$(date '+%Y-%m-%d %H:%M:%S Asia/Shanghai')
python3 - <<PY
from pathlib import Path
p=Path("$STATUS"); lines=[]
for L in p.read_text().splitlines():
  if L.startswith("**State:**"): lines.append("**State:** MAIN_AAR_DONE")
  elif L.startswith("**Updated:**"): lines.append("**Updated:** $NOW")
  else: lines.append(L)
lines.append(f"- $NOW: main AAR copied to artifacts/ ($SZ bytes); res AAR still pending manual/executor")
p.write_text("\n".join(lines)+"\n")
PY
echo "DONE main AAR $SZ bytes"
# leave res AAR for a later step / routine handoff
exit 0
