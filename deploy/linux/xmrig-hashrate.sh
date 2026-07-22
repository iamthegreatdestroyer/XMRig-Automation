#!/usr/bin/env bash
# xmrig-hashrate.sh -- quick local hashrate/health check via the XMRig HTTP API.
# Reads the port + access-token from the on-box config (0640 root:xmrig), so run as root
# or as a member of the xmrig group.  Usage: ./xmrig-hashrate.sh [/etc/xmrig/config.json]
set -euo pipefail
CONF="${1:-/etc/xmrig/config.json}"
[[ -r "$CONF" ]] || { echo "cannot read $CONF (run as root or the xmrig group)"; exit 1; }

read -r PORT TOKEN < <(python3 - "$CONF" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))["http"]
print(c.get("port",18088), c.get("access-token") or "")
PY
)

curl -fsS -H "Authorization: Bearer ${TOKEN}" "http://127.0.0.1:${PORT}/2/summary" | python3 - <<'PY'
import json,sys
d=json.load(sys.stdin)
print("hashrate 10s/60s/15m :", d.get("hashrate",{}).get("total"))
print("hugepages            :", d.get("hugepages"))
print("pool                 :", d.get("connection",{}).get("pool"))
r=d.get("results",{})
print("shares good/total    :", r.get("shares_good"), "/", r.get("shares_total"))
print("uptime (s)           :", d.get("uptime"))
PY
