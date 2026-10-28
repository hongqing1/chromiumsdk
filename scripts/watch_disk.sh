#!/bin/bash
LOG=/workspace/chromium-src-aar/logs/disk-watch.log
while true; do
  avail_kb=$(df -Pk / | awk 'NR==2{print $4}')
  avail_gb=$((avail_kb/1024/1024))
  mem=$(free -m | awk '/Mem:/{printf "avail=%sMB", $7}')
  echo "$(date '+%F %T %Z') disk_free=${avail_gb}GB $mem" >> "$LOG"
  if [ "$avail_gb" -lt 20 ]; then
    echo "STOP: disk free ${avail_gb}GB < 20GB" >> "$LOG"
    # Best-effort stop ninja
    pkill -f 'ninja -C out/AarArm64' || true
    exit 2
  fi
  sleep 60
done
