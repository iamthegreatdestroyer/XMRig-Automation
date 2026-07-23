#!/usr/bin/env bash
# xmrig busy-watchdog (CONTINUOUS) -- pauses the miner within ~3-5s when the box is busy and resumes
# it only after a sustained-idle streak (no flapping). "Busy" = CPU idle% below threshold, which fires
# for BOTH interactive builds AND ollama inference (a big memory-bound eval drops idle well below 35%,
# even though nice/CPUWeight can't arbitrate the memory bandwidth the miner also needs). This is what
# lets forge be a claim_verify/minicheck verifier without the miner starving the first (uncached) eval.
# Only ever resumes a miner that IT paused (via /run flag) -- never fights a manual `systemctl stop`.
# Runs as a long-lived Type=simple service (replaces the old 30s one-shot timer, which reacted too late).
set -uo pipefail

PAUSE_BELOW_IDLE=35    # miner RUNNING + idle% below this => box busy (a build) => PAUSE
RESUME_ABOVE_IDLE=80   # miner PAUSED  + idle% above this (sustained) => box idle => RESUME
RESUME_STREAK=4        # consecutive idle+no-inference samples required before resuming
LOOP_SLEEP=1           # extra sleep per loop; total loop period ~= 2s sample + LOOP_SLEEP
OLLAMA_PORT=11434      # an established inbound conn here = the hub is running a verify => PAUSE
UNIT=xmrig.service
FLAG=/run/xmrig-watchdog.paused
[[ -f /etc/default/xmrig-watchdog ]] && . /etc/default/xmrig-watchdog

snap(){ awk '/^cpu /{print $5+$6, $2+$3+$4+$5+$6+$7+$8+$9}' /proc/stat; }
# ollama inference is MEMORY-bandwidth-bound and leaves cores idle, so CPU-idle% misses it. The
# reliable signal is an active connection to ollama's port: claim_verify (on the hub) holds one for
# the duration of every /api/generate call. This pauses the miner the instant a verify batch starts,
# well before the expensive first (uncached) document eval -- which CPU-idle detection could not.
inferring(){ ss -Htn state established 2>/dev/null | grep -qE "[.:]${OLLAMA_PORT}[[:space:]]"; }

streak=0
while true; do
  read -r i1 t1 < <(snap); sleep 2; read -r i2 t2 < <(snap)
  idle=$(awk -v i="$((i2-i1))" -v t="$((t2-t1))" 'BEGIN{printf "%.0f", (t>0)?100*i/t:100}')
  busy=0; reason=""
  if inferring; then busy=1; reason="ollama inference"; fi
  if (( idle < PAUSE_BELOW_IDLE )); then busy=1; reason="${reason:+$reason + }idle=${idle}%"; fi
  active=$(systemctl is-active "$UNIT" 2>/dev/null || true)
  case "$active" in
    active)
      if (( busy )); then
        systemctl stop "$UNIT" && : > "$FLAG" \
          && logger -t xmrig-watchdog "PAUSE (${reason})"
      fi
      streak=0 ;;
    inactive)
      if [[ -f "$FLAG" ]]; then
        if (( ! busy )) && (( idle > RESUME_ABOVE_IDLE )); then
          streak=$((streak+1))
          if (( streak >= RESUME_STREAK )); then
            systemctl start "$UNIT" && rm -f "$FLAG" && streak=0 \
              && logger -t xmrig-watchdog "RESUME idle=${idle}% sustained, no inference"
          fi
        else
          streak=0
        fi
      fi ;;
    *) : ;;   # activating / failed: leave to systemd (Restart owns that)
  esac
  sleep "$LOOP_SLEEP"
done
