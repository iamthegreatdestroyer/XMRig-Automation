#!/usr/bin/env bash
# uninstall-xmrig.sh -- remove the XMRig miner installed by install-xmrig.sh. Run as ROOT.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

# watchdog (if installed)
systemctl disable --now xmrig-watchdog.timer 2>/dev/null || true
rm -f /etc/systemd/system/xmrig-watchdog.service /etc/systemd/system/xmrig-watchdog.timer
rm -f /opt/xmrig/xmrig-watchdog.sh /etc/default/xmrig-watchdog /run/xmrig-watchdog.paused

systemctl disable --now xmrig 2>/dev/null || true
rm -f  /etc/systemd/system/xmrig.service
rm -rf /etc/systemd/system/xmrig.service.d
systemctl daemon-reload

rm -rf /opt/xmrig /etc/xmrig
rm -f  /etc/sysctl.d/99-xmrig-hugepages.conf
sysctl -w vm.nr_hugepages=0 >/dev/null 2>&1 || true

echo "xmrig service, binary, config, and hugepage reservation removed."
echo "Optional: 'userdel xmrig'  and  'rm -rf /var/log/xmrig'  to also drop the user + logs."
