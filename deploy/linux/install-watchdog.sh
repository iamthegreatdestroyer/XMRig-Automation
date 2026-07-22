#!/usr/bin/env bash
# install-watchdog.sh -- OPTIONAL add-on: the busy-watchdog that pauses xmrig during builds and
# resumes it when the box is idle. For build nodes (e.g. sigma-forge). Run as ROOT on the box,
# AFTER install-xmrig.sh. Idempotent.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root (sudo)"; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -d -m0755 /opt/xmrig
install -m0755 "$SCRIPT_DIR/xmrig-watchdog.sh"      /opt/xmrig/xmrig-watchdog.sh
install -m0644 "$SCRIPT_DIR/xmrig-watchdog.service" /etc/systemd/system/xmrig-watchdog.service
install -m0644 "$SCRIPT_DIR/xmrig-watchdog.timer"   /etc/systemd/system/xmrig-watchdog.timer

if [[ ! -f /etc/default/xmrig-watchdog ]]; then
  cat > /etc/default/xmrig-watchdog <<'EOF'
# xmrig-watchdog thresholds = percent CPU idle over a 2s sample. Tune per box.
PAUSE_BELOW_IDLE=35     # miner running + idle% below this => box busy (build) => pause the miner
RESUME_ABOVE_IDLE=80    # miner paused  + idle% above this => box idle => resume the miner
EOF
  chmod 0644 /etc/default/xmrig-watchdog
fi

systemctl daemon-reload
systemctl enable --now xmrig-watchdog.timer

echo "watchdog installed + timer enabled (fires every 30s)."
echo "  watch : journalctl -t xmrig-watchdog -f"
echo "  tune  : /etc/default/xmrig-watchdog  (then: systemctl restart xmrig-watchdog.timer)"
echo "  remove: systemctl disable --now xmrig-watchdog.timer; rm /etc/systemd/system/xmrig-watchdog.{service,timer} /opt/xmrig/xmrig-watchdog.sh"
