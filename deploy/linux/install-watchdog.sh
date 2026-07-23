#!/usr/bin/env bash
# install-watchdog.sh -- OPTIONAL add-on: the CONTINUOUS busy-watchdog that pauses xmrig during builds
# AND during ollama inference (memory-bandwidth-bound, which CPU-idle alone misses -- it also watches for
# an active connection to the ollama port). For build/verifier nodes (e.g. sigma-forge). Run as ROOT on
# the box, AFTER install-xmrig.sh. Idempotent. Replaces the old 30s-timer model (retired below).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root (sudo)"; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# retire the old timer if a prior install left one
if systemctl list-unit-files 2>/dev/null | grep -q '^xmrig-watchdog.timer'; then
  systemctl disable --now xmrig-watchdog.timer 2>/dev/null || true
  rm -f /etc/systemd/system/xmrig-watchdog.timer
fi

install -d -m0755 /opt/xmrig
install -m0755 "$SCRIPT_DIR/xmrig-watchdog.sh"      /opt/xmrig/xmrig-watchdog.sh
install -m0644 "$SCRIPT_DIR/xmrig-watchdog.service" /etc/systemd/system/xmrig-watchdog.service

if [[ ! -f /etc/default/xmrig-watchdog ]]; then
  cat > /etc/default/xmrig-watchdog <<'EOF'
# xmrig-watchdog tunables. Idle thresholds = percent CPU idle over a 2s sample.
PAUSE_BELOW_IDLE=35     # miner running + idle% below this => box busy (build) => pause
RESUME_ABOVE_IDLE=80    # miner paused  + idle% above this (sustained) => box idle => resume
RESUME_STREAK=4         # consecutive idle+no-inference samples required before resuming
OLLAMA_PORT=11434       # an established inbound conn here => a verify batch is running => pause
EOF
  chmod 0644 /etc/default/xmrig-watchdog
fi

systemctl daemon-reload
systemctl enable --now xmrig-watchdog.service

echo "watchdog installed + continuous service enabled (reacts within ~3-5s to builds AND ollama inference)."
echo "  watch : journalctl -t xmrig-watchdog -f"
echo "  tune  : /etc/default/xmrig-watchdog  (then: systemctl restart xmrig-watchdog.service)"
echo "  remove: systemctl disable --now xmrig-watchdog.service; rm /etc/systemd/system/xmrig-watchdog.service /opt/xmrig/xmrig-watchdog.sh"
