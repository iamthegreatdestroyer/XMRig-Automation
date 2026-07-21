# XMRig Automation for Windows 11

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows%2011-blue.svg)](https://www.microsoft.com/windows)
[![XMRig](https://img.shields.io/badge/XMRig-6.22.0-orange.svg)](https://github.com/xmrig/xmrig)
[![Monero](https://img.shields.io/badge/Cryptocurrency-Monero-orange.svg)](https://www.getmonero.org/)
[![Intelligence Layer](https://img.shields.io/badge/Local%20Intelligence-LLM%20advisor-8A2BE2.svg)](#-local-intelligence-layer)

**Zero-touch XMRig Monero mining automation for Windows 11 — now with a local, privacy-preserving LLM intelligence layer.** Download XMRig, run the setup, and it mines, self-optimizes, and explains its own decisions in plain English. All inference runs locally (Ollama); nothing about your mining leaves the machine.

---

## ✨ Features

### 🚀 Zero-Touch Operation

- **One-click installation** — a single PowerShell script handles everything
- **Auto-start on boot** — mining begins automatically shortly after Windows starts
- **Auto-restart on crash** — a supervised loop keeps mining alive
- **No maintenance required** — set it and forget it

### ⚡ Performance Optimized

- **Huge pages support** — meaningful hashrate boost on RandomX
- **MSR mod** — additional RandomX performance gain
- **Adaptive thread management** — the intelligence layer tunes thread count and duty-cycles around local inference (see below)

### 🧠 Local Intelligence Layer (new)

- **LLM mining advisor** — ask "why did hashrate drop?" and get a grounded, cited answer from a *local* model
- **Nightly reflections** — an automatic, LLM-written daily summary of every mining decision
- **Deterministic decision engine** — a UCB1 bandit, thermal predictor, and profitability model make the actual calls; the LLM only *explains*, never controls
- **Zero-fabrication guardrail** — advisor answers are schema-validated against a structured decision log; unsupported claims are rejected
- **Ecosystem federation** — reflections are embedded and stored for semantic retrieval (Ollama + a vector store)

### 📊 Monitoring & Control

- **🖥️ Desktop GUI dashboard** — native PyQt6 app with real-time mining data and an "Ask the Miner" pane
- **Live hashrate tracking** — 10s / 60s / 15m averages from actual XMRig logs
- **Prometheus metrics** — real hashrate, pool latency, shares, inference latency, and admission-queue depth, scraped from XMRig's own HTTP API
- **Earnings calculator** — power-aware net projections (revenue minus electricity), not just raw H/s

### 🛠️ Lifecycle Management

- **Automated updates**, **timestamped config backups**, and a **clean uninstall** (removes scheduled tasks and exclusions)

---

## 🧠 Local Intelligence Layer

The intelligence layer is split into two strictly decoupled halves. **A deterministic engine makes every mining decision. A local LLM only reads a structured log and explains those decisions.** The LLM cannot change mining state — any action it proposes is emitted with `requires_ratification: true` and is never executed automatically. This separation is the core safety property.

### Deterministic decision engine (`intelligence/`, `ml/`)

| Module | Role |
| ------ | ---- |
| `ucb1_bandit.py` | UCB1 multi-armed bandit that optimizes thread count against a **power-aware reward** (net USD/day, not raw hashrate) |
| `admission.py` | Admission controller that duty-cycles mining (8→4 threads) around a local inference request and restores it after, via XMRig's config hot-swap |
| `ml/thermal_predictor.py` | Predictive thermal gate — defers heavy jobs when predicted temperature is too high |
| `profitability.py` | Net-revenue model (XMR revenue − electricity cost) |
| `pool_flight_table.py` | Pool selection / failover bookkeeping |
| `monte_carlo.py` | Profitability / variance simulation |
| `decision_logger.py` | Appends every decision to `logs/decision_log.jsonl` (the single source of truth the advisor reads) |

### LLM explanation engine (`intelligence/advisor.py`)

- **QUERY mode** — `granite4.1:3b`, tuned for instant, valid JSON answers to interactive questions
- **REFLECT mode** — `lfm2.5`, used for the heavier nightly reflection
- **Grounding** — answers are validated against the decision log; fabricated evidence is detected and flagged
- **Duty-cycled** — a query briefly drops mining to 4 threads, runs inference, and restores full threads (no RandomX dataset re-init for QUERY mode)

```powershell
# Ask the miner a question (grounded, local, no data leaves the machine)
python -m intelligence.advisor --ask "Why did hashrate drop most recently?"

# Run the nightly reflection now (writes logs/reflections/YYYY-MM-DD.md)
python -m intelligence.advisor --reflect

# 10-shot schema / zero-fabrication audit
python -m intelligence.advisor --audit
```

### Nightly reflection + Ollama pre-flight guard

A Windows scheduled task (**"XMRig Nightly Reflection"**, daily at 03:00) writes an LLM summary of the day's decisions. It runs through a pre-flight guard, `setup/ensure-ollama-and-reflect.ps1`, which **verifies Ollama's server is actually listening before invoking the reflection** — closing a silent-failure mode where Ollama's tray app keeps running (and auto-updates itself) but the `ollama serve` backend does not relaunch, leaving nothing on port 11434 and turning every reflection into an empty stub.

```powershell
# Register the guarded nightly-reflection task
.\setup\create-reflection-scheduled-task.ps1 -RepoPath "C:\Users\YOUR_USERNAME\XMRig-Automation"
```

---

## 🎯 Quick Start

### 1. Download XMRig

Download the latest XMRig from the [official GitHub releases](https://github.com/xmrig/xmrig/releases) and extract to `C:\XMRig\`.

### 2. Run Master Setup

```powershell
# Open PowerShell as Administrator
cd C:\Users\YOUR_USERNAME\XMRig-Automation
.\MASTER-SETUP.ps1
```

### 3. Restart Computer

After setup completes, restart to enable huge pages for optimal performance. **Mining starts automatically on every boot.**

### 4. (Optional) Enable the Intelligence Layer

```powershell
# Install Ollama (https://ollama.com) and pull the two models:
ollama pull granite4.1:3b      # interactive QUERY mode
ollama pull lfm2.5             # nightly REFLECT mode

# Install Python deps and register the guarded nightly reflection:
pip install -r dashboard/requirements.txt
.\setup\create-reflection-scheduled-task.ps1 -RepoPath "$PWD"
```

### 5. (Optional) Launch the Desktop Dashboard

```powershell
.\START-DASHBOARD.ps1
```

See [`dashboard/README-DASHBOARD.md`](dashboard/README-DASHBOARD.md) for complete dashboard documentation.

---

## 📋 System Requirements

### Hardware

- **CPU:** AMD Ryzen or Intel processor (8+ threads recommended)
- **RAM:** 8 GB minimum; **16 GB+ recommended** if running the intelligence layer (the LLMs load into RAM)
- **Storage:** ~1 GB for XMRig + logs; several GB more for local models
- **Internet:** stable connection for pool communication

### Software

- **OS:** Windows 10/11 (64-bit)
- **PowerShell:** 5.1 or higher
- **.NET Framework:** 4.7.2 or higher
- **Administrator access:** required for setup (huge pages / MSR)
- **Python:** 3.x — required for the dashboard and intelligence layer
- **Ollama:** required for the intelligence layer (local LLM inference)

### Tested Configuration

- **CPU:** AMD Ryzen 7 7730U (8 cores, 16 threads)
- **RAM:** 32 GB
- **OS:** Windows 11 Pro
- **Measured hashrate:** ~1,150–1,250 H/s (RandomX, 8 threads, as run by the intelligence layer)

---

## 📁 Project Structure

```
XMRig-Automation/
├── MASTER-SETUP.ps1                 # Main orchestration script
├── ENABLE-HUGEPAGES.ps1             # Huge pages enabler
├── START-DASHBOARD.ps1              # Desktop dashboard launcher
├── .gitignore
│
├── config/                          # Configuration
│   ├── config.json                  # Optimized XMRig config
│   ├── config-template.json         # Template with placeholders
│   └── CONFIG-EXPLAINED.md
│
├── intelligence/                    # 🧠 Deterministic decision engine + LLM advisor
│   ├── advisor.py                   # LLM explanation engine (QUERY/REFLECT, grounded)
│   ├── ucb1_bandit.py               # Power-aware thread-count optimizer
│   ├── admission.py                 # Duty-cycle admission controller
│   ├── profitability.py             # Net-revenue (power-aware) model
│   ├── pool_flight_table.py         # Pool selection / failover
│   ├── monte_carlo.py               # Profitability simulation
│   ├── decision_logger.py           # Structured decision log writer
│   └── ryzanstein_sync.py           # Reflection → vector-store federation
│
├── ml/
│   └── thermal_predictor.py         # Predictive thermal gate
│
├── dashboard/                       # Desktop GUI + metrics
│   ├── mining-dashboard.py          # PyQt6 app ("Ask the Miner" pane)
│   ├── prometheus_metrics.py        # Metric registry
│   ├── prometheus_metrics_server.py # Metrics server (reads XMRig's live API)
│   ├── requirements.txt
│   └── README-DASHBOARD.md
│
├── setup/                           # Setup scripts
│   ├── install.ps1
│   ├── configure-defender.ps1
│   ├── configure-hugepages.ps1
│   ├── create-scheduled-task.ps1            # Mining auto-start
│   ├── create-reflection-scheduled-task.ps1 # Nightly reflection (guarded)
│   └── ensure-ollama-and-reflect.ps1        # Ollama pre-flight guard
│
├── scripts/                         # Mining control scripts
├── tools/                           # update / backup / uninstall
├── tests/                           # pytest suite (advisor, bandit, admission, thermal, worker)
├── logs/                            # decision_log.jsonl + reflections/ (git-ignored)
└── docs/                            # README / FAQ / TROUBLESHOOTING
```

---

## 🔧 Configuration

### Default Settings

- **Pool:** pool.hashvault.pro:3333
- **Algorithm:** RandomX (rx/0)
- **Threads:** managed by the intelligence layer (8 physical cores, duty-cycled during inference)
- **Huge Pages:** enabled
- **Donation:** 1% to XMRig developers

Edit `config/config.json` to change the pool URL, wallet address, thread configuration, pool password/rig ID, and the XMRig HTTP API (host/port/access-token) that the dashboard and metrics server read.

---

## 📊 Performance

| Metric               | Value                                    |
| -------------------- | ---------------------------------------- |
| **Hashrate**         | ~1,150–1,250 H/s measured (Ryzen 7 7730U, 8 threads) |
| **Threads**          | 8 physical cores (→4 during LLM inference) |
| **Temperature**      | thermally gated (heavy jobs deferred when hot) |
| **Reward metric**    | net USD/day (revenue − electricity)      |

_Higher raw hashrate is possible with all 16 threads + huge pages, at the cost of system responsiveness. Performance varies by hardware and pool difficulty._

---

## 🧪 Testing

```powershell
# Unit tests (advisor, bandit, admission controller, thermal predictor, dashboard worker)
python -m pytest tests/ -q

# Dashboard logic smoke test
python test-dashboard-logic.py

# Advisor zero-fabrication audit
python -m intelligence.advisor --audit
```

---

## 💰 Pool Information

### Current Pool: HashVault

- **URL:** pool.hashvault.pro:3333
- **Fee:** 0.9%
- **Minimum Payout:** 0.1 XMR
- **Dashboard:** https://hashvault.pro/monero

Visit the pool dashboard and enter your wallet address to view hashrate, shares, pending balance, and payment history.

---

## 🛡️ Security & Legal

- **Antivirus false positives:** XMRig is often flagged as a PUP. `setup/configure-defender.ps1` adds Windows Defender exclusions; add exclusions manually for third-party AV.
- **Local-only inference:** the intelligence layer runs entirely on-device via Ollama. No mining data, prompts, or reflections are sent to any external AI service.
- **Privacy:** your wallet address is stored locally in `config.json`; only the wallet address is shared with the pool (pool stats are public).
- **Legal:** mine only on hardware you own; check local electricity costs and regulations. Provided as-is without warranty.

---

## ❓ Troubleshooting

### Nightly reflections are empty ("model returned no output")

Ollama's server isn't listening. Ollama's Windows tray app can keep running (and auto-update itself) while the `ollama serve` backend stays down after an update, reboot, or sleep — so nothing listens on port 11434. Start it with `ollama serve`, or rely on the pre-flight guard (`setup/ensure-ollama-and-reflect.ps1`) that the reflection task uses to auto-start it.

### XMRig not starting

- Verify `xmrig.exe` exists in `C:\XMRig\xmrig-6.22.0\`
- Check Windows Defender hasn't quarantined it; run `setup/configure-defender.ps1`

### Low hashrate

- Ensure huge pages are enabled (restart required) and setup ran as Administrator (MSR mod)
- Verify the CPU isn't thermal-throttling

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for comprehensive solutions.

---

## 📖 Documentation

- **[docs/README.md](docs/README.md)** — complete project guide
- **[docs/FAQ.md](docs/FAQ.md)** — common questions
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — problem-solving
- **[config/CONFIG-EXPLAINED.md](config/CONFIG-EXPLAINED.md)** — configuration reference
- **[dashboard/README-DASHBOARD.md](dashboard/README-DASHBOARD.md)** — dashboard docs

---

## 🤝 Contributing

Contributions are welcome — fork, branch, test thoroughly, and open a pull request.

---

## 📜 License

MIT License — see [LICENSE](LICENSE).

### Third-Party Software

- **XMRig:** GPL-3.0 — https://github.com/xmrig/xmrig
- **Monero:** BSD-3-Clause — https://github.com/monero-project/monero
- **Ollama:** MIT — https://github.com/ollama/ollama

---

## ⚠️ Disclaimer

This software is provided for educational purposes. Cryptocurrency mining consumes electricity, generates heat, may violate workplace policies, and is not profitable on most consumer hardware. **Use at your own risk** — the authors are not responsible for hardware damage, electricity costs, lost earnings, or policy/legal violations.

---

**Version:** 1.2.0 (Local Intelligence Layer + Ecosystem Federation)
**Last Updated:** July 21, 2026
**Repository:** https://github.com/iamthegreatdestroyer/XMRig-Automation

**Happy Mining! 🚀⛏️**
