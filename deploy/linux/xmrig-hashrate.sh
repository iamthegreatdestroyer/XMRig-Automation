#!/usr/bin/env bash
# xmrig-hashrate.sh -- quick local hashrate/health check via the XMRig HTTP API.
# Reads port + access-token from the on-box config (0640 root:xmrig), so run with sudo
# (or as a member of the xmrig group).  Usage: sudo ./xmrig-hashrate.sh [/etc/xmrig/config.json]
set -euo pipefail
CONF="${1:-/etc/xmrig/config.json}"
[[ -r "$CONF" ]] || { echo "cannot read $CONF (run with sudo, or as the xmrig group)"; exit 1; }

PORT="$(grep -oP '"port"\s*:\s*\K[0-9]+' "$CONF" | head -1)"; PORT="${PORT:-18088}"
TOKEN="$(grep -oP '"access-token"\s*:\s*"\K[^"]+' "$CONF" || true)"

curl -fsS -H "Authorization: Bearer ${TOKEN}" "http://127.0.0.1:${PORT}/2/summary" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("hashrate 10s/60s/15m :", d.get("hashrate",{}).get("total"))
print("hugepages (alloc/tot):", d.get("hugepages"))
print("mining threads       :", len(d.get("hashrate",{}).get("threads",[])) or d.get("cpu",{}).get("threads"))
print("pool                 :", d.get("connection",{}).get("pool"))
r=d.get("results",{})
print("shares good/total    :", r.get("shares_good"),"/",r.get("shares_total"))
print("uptime (s)           :", d.get("uptime"))
'
