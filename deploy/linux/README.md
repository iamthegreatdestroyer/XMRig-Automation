# Linux Deploy Kit — XMRig on the Sigma nodes

Unprivileged, sandboxed XMRig (Monero / RandomX) as a `systemd` service on the idle Linux boxes,
mining to the **same pool + wallet** as the Windows miner. Built to be safe on machines that also
run real work: dedicated `xmrig` user, **no root and no capabilities at runtime**, and it **yields
instantly** to builds / interactive use.

## Honest economics (read first)
At these CPUs' modest RandomX hashrate this is **net-negative** — the electricity to run them
flat-out very likely exceeds the XMR earned. Worth it for using idle compute / the hobby / feeding
the intelligence layer, **not as income**. Benchmark real hashrate after deploy before assuming otherwise.

## Which boxes
| Box | CPU | Deploy? |
|---|---|---|
| **sigma-studio** (.7) | i5-4690K, 4 desktop cores | ✅ best candidate |
| **sigma-forge** (.5) | i7-8650U, 4c/8t **mobile** — a BUILD node | ✅ with `--forge` (yields to builds; throttles) |
| sigma-infer (.6) | i7-8650U, only ~2.7G RAM free, job = inference | ❌ skip |
| sigma-pi (.2) | Pi 5 ARM, runs DNS | ❌ tiny hashrate |
| **sigma-box hub** (.1) | 2-core, already saturated, live spine | ❌ **never** |

## Security model
`randomx.rdmsr/wrmsr = false` (no MSR mod → no root/CAP_SYS_RAWIO at runtime). Hugepages work
unprivileged via `LimitMEMLOCK=infinity`. Costs ~5-10% hashrate on these Intel chips vs a rooted
MSR miner — deliberately traded for a fully sandboxed service. The only secret is a per-box API
token (localhost-only, restricted); the wallet is a public receive address.

## Prerequisites (per box)
- Debian with `systemd`; `curl`, `openssl`, `tar` (and `python3` for JSON validation) present.
- Outbound HTTPS (:443) to the pool.
- Root access on the box (interactive password — no passwordless sudo needed).
- The wallet: create `deploy.env` from `deploy.env.example` (already done locally if you cloned the
  private kit), **or** pass `--wallet <addr>` to the installer.

## Deploy (canary: studio first, then forge)

```bash
# --- from your workstation: copy the kit up (includes the gitignored deploy.env) ---
scp -r deploy/linux sigma-studio:/tmp/xmrig-deploy

# --- on the box, as root ---
ssh sigma-studio
su -                      # (or sudo -i) — become root
cd /tmp/xmrig-deploy
./install-xmrig.sh --rig-id sigma-studio --threads 100
#   downloads XMRig 6.22.0 static, VERIFIES the pinned SHA256 (hard-fail on mismatch),
#   creates the xmrig user, renders /etc/xmrig/config.json with a fresh API token,
#   reserves hugepages, installs the unit. Does NOT start it.

# --- canary: start + watch (not enabled on boot yet) ---
systemctl start xmrig
journalctl -u xmrig -f    # want:  'huge pages 100% (1200/1200)'  then  'accepted (N/N)'
./xmrig-hashrate.sh       # local API summary

# --- once it's accepting shares with full hugepages, persist across reboots ---
systemctl enable xmrig
```

**forge** is identical but with the mobile/build-node profile:
```bash
scp -r deploy/linux sigma-forge:/tmp/xmrig-deploy
ssh sigma-forge ; su - ; cd /tmp/xmrig-deploy
./install-xmrig.sh --rig-id sigma-forge --threads 50 --forge
# then the same start → verify → (yield test) → enable
```

## Verify
- `systemctl status xmrig` → active; `systemctl show xmrig -p LimitMEMLOCK -p CPUWeight -p Nice` → `infinity / 1 / 19`.
- **Hugepages (critical):** journal shows `huge pages 100% (1200/1200)` — NOT `0%` or a partial fraction.
- **Shares:** `accepted (N/N)` lines; non-zero `speed 10s/60s/15m`.
- **Pool dashboard:** hashvault.pro → your wallet → `sigma-studio` / `sigma-forge` appear beside the Windows `RyzenRig`.
- **forge yield test (before `enable`):** run a build (or `stress-ng --cpu 4 --timeout 60`) and confirm in `htop` that the build gets the cores while `xmrig` (NI 19) collapses to ~0%, then ramps back when idle.

## Roll back
```bash
systemctl disable --now xmrig     # instant stop, off boot
./uninstall-xmrig.sh              # full removal (binary, config, unit, hugepage reservation)
```
studio and forge are independent — a problem on one never touches the other.

## Files
| File | Role |
|---|---|
| `install-xmrig.sh` | root installer (verify → user → binary → render config → hugepages → unit); no auto-start |
| `uninstall-xmrig.sh` | full removal |
| `xmrig-hashrate.sh` | local API hashrate/health check |
| `config/config-linux-template.json` | tracked template (placeholders; rdmsr/wrmsr off; 2 pools) |
| `xmrig.service` | hardened unprivileged unit (see the "DO NOT ADD" note inside — 3 directives silently kill RandomX) |
| `xmrig.service.d/10-forge.conf` | forge-only `CPUQuota=300%` |
| `sysctl/99-xmrig-hugepages.conf` | `vm.nr_hugepages = 1200` |
| `xmrig-6.22.0-linux-static-x64.sha256` | pinned official checksum |
| `deploy.env.example` | template for the (gitignored) `deploy.env` holding the public wallet |

## Optional follow-on
Central monitoring: bind the API additionally on the wg0 IP + add a Prometheus target, or point the
repo's `dashboard/prometheus_metrics_server.py` at each box's `127.0.0.1:18088`. Not part of the base deploy.
