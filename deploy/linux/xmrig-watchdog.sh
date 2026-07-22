#!/usr/bin/env bash
# xmrig-watchdog.sh -- pause the miner when the box is genuinely busy (e.g. a build) and resume it
# when the box goes idle again. Uses a 2-second CPU-idle sample (responsive; NOT the laggy 1-min
# load average). Only ever resumes a miner that IT paused -- it never fights a manual
# `systemctl stop xmrig`. Runs as root via xmrig-watchdog.timer (every 30s).
#
# Why this exists: Nice/CPUWeight/CPUQuota only make the miner yield PARTIALLY, because interactive
# builds run in user.slice while the miner is in system.slice (peer cgroup slices split the CPU
# ~50/50). Fully protecting builds needs an explicit pause-when-busy signal -- this.
set -euo pipefail

# Thresholds = percent CPU idle over a 2s sample. Override in /etc/default/xmrig-watchdog.
PAUSE_BELOW_IDLE=35    # miner RUNNING + idle% below this => box busy beyond the miner => PAUSE
RESUME_ABOVE_IDLE=80   # miner PAUSED  + idle% above this => box idle => RESUME
UNIT=xmrig.service
FLAG=/run/xmrig-watchdog.paused
[[ -f /etc/default/xmrig-watchdog ]] && . /etc/default/xmrig-watchdog

# 2-second CPU idle% from /proc/stat: idle+iowait over total, delta across the interval.
snap(){ awk '/^cpu /{print $5+$6, $2+$3+$4+$5+$6+$7+$8+$9}' /proc/stat; }
read -r i1 t1 < <(snap); sleep 2; read -r i2 t2 < <(snap)
idle=$(awk -v i="$((i2-i1))" -v t="$((t2-t1))" 'BEGIN{printf "%.0f", (t>0)?100*i/t:100}')

active=$(systemctl is-active "$UNIT" 2>/dev/null || true)
case "$active" in
  active)
    if (( idle < PAUSE_BELOW_IDLE )); then
      systemctl stop "$UNIT" && : > "$FLAG"
      logger -t xmrig-watchdog "PAUSE  idle=${idle}% < ${PAUSE_BELOW_IDLE}% (box busy)"
    fi ;;
  inactive)
    if [[ -f "$FLAG" ]] && (( idle > RESUME_ABOVE_IDLE )); then
      systemctl start "$UNIT" && rm -f "$FLAG"
      logger -t xmrig-watchdog "RESUME idle=${idle}% > ${RESUME_ABOVE_IDLE}% (box idle)"
    fi ;;
  *) : ;;   # activating / failed / unknown: leave it to systemd (Restart=on-failure owns that)
esac
