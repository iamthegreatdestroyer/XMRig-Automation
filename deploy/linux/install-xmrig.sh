#!/usr/bin/env bash
# install-xmrig.sh -- deploy an UNPRIVILEGED XMRig systemd miner on a Debian box (studio/forge).
# Run as ROOT on the target box. Idempotent-ish. Does NOT auto-start (you review, then start).
#
#   sudo ./install-xmrig.sh --rig-id sigma-studio --threads 100
#   sudo ./install-xmrig.sh --rig-id sigma-forge  --threads 50 --forge
#
# Wallet: from --wallet <addr>, or a WALLET_ADDRESS= line in ./deploy.env (gitignored), or the
# WALLET_ADDRESS env var. It is a PUBLIC Monero receive address (no keys/funds exposed).
set -euo pipefail

XMRIG_VERSION="6.22.0"
ARCHIVE="xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz"
URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/${ARCHIVE}"
SHA_FILE="xmrig-${XMRIG_VERSION}-linux-static-x64.sha256"
PREFIX="/opt/xmrig"
CONF_DIR="/etc/xmrig"
LOG_DIR="/var/log/xmrig"
SVC_USER="xmrig"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RIG_ID=""; THREADS=""; WALLET="${WALLET_ADDRESS:-}"; FORGE=0

log(){ printf '  [%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die(){ printf '  ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rig-id)  RIG_ID="${2:?}"; shift 2;;
    --threads) THREADS="${2:?}"; shift 2;;
    --wallet)  WALLET="${2:?}"; shift 2;;
    --forge)   FORGE=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0;;
    *) die "unknown arg: $1 (see --help)";;
  esac
done

[[ $EUID -eq 0 ]] || die "run as root (su - / sudo -i): $0"

# wallet fallback: deploy.env next to this script
if [[ -z "$WALLET" && -f "$SCRIPT_DIR/deploy.env" ]]; then
  WALLET="$(set -a; . "$SCRIPT_DIR/deploy.env" >/dev/null 2>&1; printf '%s' "${WALLET_ADDRESS:-}")"
fi
[[ -n "$RIG_ID"  ]] || die "--rig-id required (e.g. sigma-studio / sigma-forge)"
[[ -n "$THREADS" ]] || die "--threads required (studio=100, forge=50)"
[[ "$THREADS" =~ ^[0-9]+$ ]] || die "--threads must be an integer (max-threads-hint percent)"
[[ -n "$WALLET"  ]] || die "wallet required: pass --wallet <addr>, set WALLET_ADDRESS, or create deploy.env"
[[ "$WALLET" =~ ^4[0-9A-Za-z]{94}$ ]] || die "wallet does not look like a standard Monero address (95 chars, starts with 4)"

command -v curl    >/dev/null || die "curl missing (apt-get install -y curl)"
command -v openssl >/dev/null || die "openssl missing (apt-get install -y openssl)"
command -v tar     >/dev/null || die "tar missing"

# 1. fetch + verify binary (pinned SHA256; NO pipe-to-shell) -----------------------------------
cd "$SCRIPT_DIR"
[[ -f "$SHA_FILE" ]] || die "pinned checksum file '$SHA_FILE' not found next to this script"
if [[ ! -f "$ARCHIVE" ]]; then
  log "downloading $ARCHIVE ..."
  curl -fL --proto '=https' --tlsv1.2 -o "$ARCHIVE" "$URL"
fi
log "verifying pinned SHA256 ..."
sha256sum -c "$SHA_FILE" || die "SHA256 mismatch on $ARCHIVE -- refusing to install (tamper/corruption)"

# 2. dedicated system user (no login, no home) -------------------------------------------------
id "$SVC_USER" &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin "$SVC_USER"

# 3. install binary ----------------------------------------------------------------------------
install -d -m0755 "$PREFIX"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tar -xf "$ARCHIVE" -C "$tmp"
install -m0755 "$tmp/xmrig-${XMRIG_VERSION}/xmrig" "$PREFIX/xmrig"
log "binary installed: $("$PREFIX/xmrig" --version 2>/dev/null | head -1)"

# 4. render on-box config with a fresh per-box API token ---------------------------------------
install -d -m0750 -o root      -g "$SVC_USER" "$CONF_DIR"
install -d -m0750 -o "$SVC_USER" -g "$SVC_USER" "$LOG_DIR"
TOKEN="$(openssl rand -hex 32)"   # hex = sed-safe, 256-bit
umask 077
sed -e "s/{{RIG_ID}}/${RIG_ID}/g" \
    -e "s/{{MAX_THREADS_HINT}}/${THREADS}/g" \
    -e "s#{{LOG_FILE_PATH}}#${LOG_DIR}/xmrig.log#g" \
    -e "s#{{WALLET_ADDRESS}}#${WALLET}#g" \
    -e "s#__API_TOKEN__#${TOKEN}#g" \
    "$SCRIPT_DIR/config/config-linux-template.json" > "$CONF_DIR/config.json"
chown root:"$SVC_USER" "$CONF_DIR/config.json"; chmod 0640 "$CONF_DIR/config.json"
if command -v python3 >/dev/null; then
  python3 -c "import json;json.load(open('$CONF_DIR/config.json'))" \
    || die "rendered $CONF_DIR/config.json is not valid JSON (check the template)"
fi
log "config rendered: $CONF_DIR/config.json  (rig-id=$RIG_ID, threads=$THREADS, API localhost:18088 restricted)"

# 5. reserve hugepages (persistent, boot-time) -------------------------------------------------
install -m0644 "$SCRIPT_DIR/sysctl/99-xmrig-hugepages.conf" /etc/sysctl.d/99-xmrig-hugepages.conf
sysctl --system >/dev/null
hp="$(awk '/HugePages_Total/{print $2}' /proc/meminfo)"
if [[ "${hp:-0}" -ge 1200 ]]; then
  log "hugepages reserved: HugePages_Total=$hp"
else
  log "WARN: HugePages_Total=$hp (< 1200) -- memory fragmentation? A REBOOT reserves them at boot for full RandomX speed."
fi

# 6. systemd unit (+ optional forge drop-in) ---------------------------------------------------
install -m0644 "$SCRIPT_DIR/xmrig.service" /etc/systemd/system/xmrig.service
if [[ "$FORGE" -eq 1 ]]; then
  install -d -m0755 /etc/systemd/system/xmrig.service.d
  install -m0644 "$SCRIPT_DIR/xmrig.service.d/10-forge.conf" /etc/systemd/system/xmrig.service.d/10-forge.conf
  log "forge drop-in installed (CPUQuota=300%)"
fi
systemctl daemon-reload

cat <<EONEXT

  ================= INSTALLED (review, then start) =================
  config : $CONF_DIR/config.json    (rig-id=$RIG_ID, threads=$THREADS)
  binary : $PREFIX/xmrig            unit: /etc/systemd/system/xmrig.service

  Canary start (NOT enabled on boot yet):
      systemctl start xmrig
      journalctl -u xmrig -f        # want: 'huge pages 100%' + 'accepted (N/N)'
  Local hashrate check:
      $SCRIPT_DIR/xmrig-hashrate.sh
  Once you see accepted shares + full hugepages, persist across reboots:
      systemctl enable xmrig
  Roll back any time:
      systemctl disable --now xmrig      # or: $SCRIPT_DIR/uninstall-xmrig.sh
  =================================================================
EONEXT
