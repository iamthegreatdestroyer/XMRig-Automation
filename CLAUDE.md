# CLAUDE.md — XMRig-Automation

## Project
- **Name:** XMRig-Automation
- **Language:** PowerShell 5.1+ and Python 3.x
- **Platform:** Windows 11 Pro
- **Mission:** Zero-touch Monero mining automation with native desktop dashboard

## Status: Production-Ready — v1.0.0

### Completed Phases

- [x] **Core setup** — `MASTER-SETUP.ps1` orchestrates full install: XMRig download, Windows Defender exclusions, huge pages, scheduled auto-start task
- [x] **Mining control** — start/stop/restart scripts, auto-restart loop, desktop shortcuts
- [x] **Desktop dashboard** — `dashboard/mining-dashboard.py` (PyQt6), launched via `START-DASHBOARD.ps1`; live hashrate/CPU/memory/earnings from XMRig log
- [x] **Advanced layer** — `advanced/optimizer-v3.ps1` (autonomous thread optimizer), `advanced/profit-switcher-v2.ps1` (pool switcher)
- [x] **Tooling** — update, backup, uninstall scripts in `tools/`
- [x] **Documentation** — README, FAQ, TROUBLESHOOTING, CONFIG-EXPLAINED

## Done Criteria

- [x] `MASTER-SETUP.ps1` runs without syntax errors
- [x] All root-level `.ps1` scripts pass PowerShell parser (17/17 OK)
- [x] `test-dashboard-logic.py` passes all 5 checks (XMRig process, log parse, system stats, earnings calc, dashboard compile)
- [x] v1.0.0 tagged

## Key Paths
- XMRig binary: `C:\XMRig\xmrig-6.22.0\xmrig.exe`
- XMRig log: `C:\XMRig\xmrig-6.22.0\xmrig.log`
- Config: `config/config.json` — pool, wallet, thread count
- Dashboard: `dashboard/mining-dashboard.py`

## Development Rules
- Do not refactor working scripts — only fix bugs
- Never commit secrets (wallet address is in `config/config.json`, not source-controlled with real values)
- Test with `python test-dashboard-logic.py` before any dashboard changes
- Run PS1 syntax check before committing: `Get-ChildItem *.ps1 | ForEach-Object { ... Parser::ParseFile ... }`

## Completion Signal
```
git tag v1.0.0 && git push origin v1.0.0
```
