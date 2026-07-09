# Phase 4 Handoff — XMRig-Automation Local Intelligence Layer

**Written:** 2026-07-08, by a Claude session with no relationship to the ecosystem-wide
session this hands off to. **Assume zero context transfer.** Every claim below was either
freshly re-verified by running a real command moments before writing it (verbatim output
pasted), or is explicitly marked as unverified. **Do not trust anything in this document
without re-running the verification commands yourself first** — that includes the "Done
and verified" bucket. This document describes a point-in-time snapshot; re-run everything.

---

## 0. Exact Current State (verbatim, not paraphrased)

Run these yourself before reading further. Output below is from the actual run that
produced this document.

```
$ cd C:\Users\sgbil\XMRig-Automation
$ git log --oneline -10
84fa821 feat: Local Intelligence Layer — Sprint 3 complete (all done-criteria verified live)
ddbab3d feat: Local Intelligence Layer — Sprint 1-2 complete, Sprint 3 in progress
eddc88d Add CLAUDE.md; production-ready v1.0.0
3d8a21d feat: intelligence layer, security hardening, config optimizations
b43ff85 feat: Implement XMRig Automation Production Web Dashboard and Metrics Server
4fd8071 feat: Add centralized port configuration for XMRig automation
b025776 Add master launcher and individual scripts for XMRig mining suite
46c5bc2 docs: Add Verus compatibility issue documentation and recommendations
c054fd3 fix: Update Verus pools to working alternatives
1ed1d46 fix: Update XMRig path to xmrig-6.22.0 subdirectory and add profit switcher status tracking

$ git status
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
	deleted:    .history/dashboard/mining-dashboard_20251005204725.py
	deleted:    .history/dashboard/mining-dashboard_20251005205540.py
	deleted:    .history/dashboard/mining-dashboard_20251005213600.py
	deleted:    .history/dashboard/mining-dashboard_20251005213616.py
	deleted:    .history/dashboard/mining-dashboard_20251005213941.py
	deleted:    .history/dashboard/mining-dashboard_20251005220825.py
	deleted:    .history/dashboard/mining-dashboard_20251005220854.py
	deleted:    .history/dashboard/mining-dashboard_20251005220906.py
	deleted:    .history/dashboard/mining-dashboard_20251005221644.py
	deleted:    .history/dashboard/mining-dashboard_20251005221657.py
	deleted:    .history/dashboard/mining-dashboard_20251005222138.py
	deleted:    .history/dashboard/xmrig_api_client_20251223160431.py
	deleted:    .history/dashboard/xmrig_api_client_20251223162751.py
	deleted:    .history/dashboard/xmrig_api_client_20251223172427.py
	deleted:    .history/dashboard/xmrig_api_client_20251223172514.py
	deleted:    .history/dashboard/xmrig_api_client_20251223172603.py
	deleted:    .history/dashboard/xmrig_api_client_20251223172654.py
	deleted:    .history/dashboard/xmrig_api_client_20251223173909.py

Untracked files:
	.history/bench/
	.history/dashboard/mining-dashboard_20260706200727.py
	.history/dashboard/mining-dashboard_20260706200801.py
	.history/dashboard/mining-dashboard_20260706202257.py
	.history/dashboard/xmrig_api_client_20260706191259.py
	.history/dashboard/xmrig_api_client_20260706191308.py
	.history/dashboard/xmrig_api_client_20260706191854.py
	.history/intelligence/
	.history/tests/

no changes added to commit

$ git branch --show-current
main

$ git tag -l
v1.0.0
v1.1.0

$ git ls-remote --tags origin
eddc88d6eb46d983852858e707bf93b675a002c9	refs/tags/v1.0.0
3a54b26b9030d3845d35f4f0ebc859265a87f42f	refs/tags/v1.1.0
84fa82127b95206d8d00c123e3c4d5915b2f07bb	refs/tags/v1.1.0^{}
```

**Interpretation, not fact-repetition:** `origin/main` HEAD matches local HEAD (`84fa821`).
The `v1.1.0` tag is pushed and points at `84fa821` on the remote (confirmed via
`git ls-remote`, not just a local tag that might not exist upstream). The only
uncommitted state is `.history/` churn (VS Code's local-history feature, pre-existing
noise, deliberately never touched — see §5). **There is no feature branch** — all Phase
1-3 work landed directly on `main`. If you want Phase 4 isolated, you must create a
branch yourself; none exists.

**Repo location:** `C:\Users\sgbil\XMRig-Automation` (this machine). **Original plan
doc lives OUTSIDE git**, at `F:\Projects\XMRig\Local Intelligence Layer v2.txt` — you
need filesystem access to this machine's `F:\` drive to read it, it is not in the repo
and not on GitHub.

---

## 1. Done and Verified

Everything in this section: I ran the command myself, just now, and the output below is
real, not recalled from memory of an earlier session.

### 1.1 Full test suite passes
```
$ python -m pytest tests/ -v
============================= test session starts =============================
...
tests/test_admission.py::TestAdmissionStateMachine::test_canary_flag_persists_on_no_recovery PASSED
tests/test_admission.py::TestAdmissionStateMachine::test_decisions_are_logged PASSED
tests/test_admission.py::TestAdmissionStateMachine::test_inference_error_still_restores_mining PASSED
tests/test_admission.py::TestAdmissionStateMachine::test_miner_not_running_skips_xmrig_control PASSED
tests/test_admission.py::TestAdmissionStateMachine::test_query_cycle_mining_to_query_to_mining PASSED
tests/test_admission.py::TestAdmissionStateMachine::test_queue_drains_when_gate_clears PASSED
tests/test_admission.py::TestAdmissionStateMachine::test_reflect_job_uses_pause_resume PASSED
tests/test_admission.py::TestAdmissionStateMachine::test_thermal_gate_queues_instead_of_dropping PASSED
tests/test_advisor.py (12 tests) PASSED
tests/test_advisor_worker.py (4 tests) PASSED
tests/test_thermal_predictor.py (5 tests) PASSED
tests/test_ucb1_bandit.py (10 tests) PASSED
============================= 39 passed in 46.84s ==============================
```
Command to re-run: `cd C:\Users\sgbil\XMRig-Automation && python -m pytest tests/ -v`

### 1.2 Repo's own required test passes
```
$ python test-dashboard-logic.py
[1/5] XMRig process found (PID: 29088), Uptime: 50h 39m
[2/5] Log fresh (6.1s old), hashrate 1406.5 H/s (10s), shares 6177 accepted / 11 rejected
[3/5] CPU 85.8%, Memory 23.9/31.3 GB
[4/5] Earnings calc: 1900 H/s -> 0.002 XMR/day ($0.65)
[5/5] Dashboard module compiles, no syntax errors
SUMMARY: Everything looks good.
```
This is the repo's own CLAUDE.md-mandated pre-commit check (`CLAUDE.md` line 24, 36).
Command: `python test-dashboard-logic.py`

### 1.3 XMRig is live, undisturbed, mining normally
PID 29088, started 2026-07-06 19:19:24, uptime 50h39m at time of writing — **same PID
across the entire Phase 1-3 implementation**, confirming nothing in this work has
crashed or restarted the miner. Verify: `Get-Process xmrig` (PowerShell).

### 1.4 Power-aware bandit wiring — code + behavior
- `intelligence/ucb1_bandit.py:99` — `def auto_record(state)`: measures live hashrate,
  calls `profitability.power_aware_reward()`, records **USD/day net profit**, not raw H/s.
- `intelligence/ucb1_bandit.py:55` — `def _cores_for_hint(hint)`: maps an arm's hint% to
  an explicit `cpu.rx` core list (physical cores first, SMT siblings only past 8 threads).
- `intelligence/ucb1_bandit.py:77` — `def _read_current_hint()`: derives the live arm from
  `cpu.rx` length (not the dead `max-threads-hint` field), returns `None` during
  admission.py's transient 4-thread QUERY state rather than misattributing a measurement.
- Verified via `tests/test_ucb1_bandit.py` (10/10 passing, §1.1) **and** a real invocation
  against the live miner during Phase 3 (not re-run for this handoff, but the test suite
  covers the same logic paths with the live miner mocked).

### 1.5 Thermal predictor decision-logging
- `ml/thermal_predictor.py:14` — `_log_decision()` helper.
- Called at lines 107 (`should_throttle` verdict-change), 185, 201 (`ThermalController`
  thread reduce/increase actions).
- Verified: `tests/test_thermal_predictor.py` (5/5 passing, §1.1) — confirms logging fires
  only on state transitions, not every poll.

### 1.6 Dashboard "Ask the Miner" — AdvisorWorker
- `dashboard/mining-dashboard.py:305` — `class AdvisorWorker(QThread)`.
- This class was **completely missing** before Phase 3 (referenced but undefined —
  `NameError` on click). Now exists and is unit-tested: `tests/test_advisor_worker.py`
  (4/4 passing, §1.1), including an explicit regression test
  (`test_exception_never_escapes_run`) for the exact failure mode that used to crash
  the whole dashboard process.
- **Not re-verified via live UI click in this handoff session** — it was verified live
  (typed a real question, clicked Ask, watched a real duty cycle, got a real grounded
  answer) during Phase 3 implementation, not re-run just now. The unit tests above ARE
  freshly re-run. If you want live-UI proof, re-run it yourself.

### 1.7 Nightly reflection scheduler — exists, registered, has fired twice for real
```
$ (Get-ScheduledTask -TaskName "XMRig Nightly Reflection") | Select TaskName, State
TaskName : XMRig Nightly Reflection
State    : Ready

$ (Get-ScheduledTask -TaskName "XMRig Nightly Reflection" | Get-ScheduledTaskInfo) |
    Select LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
LastRunTime        : 7/8/2026 6:00:01 AM
LastTaskResult     : 0
NextRunTime        : 7/9/2026 3:00:00 AM
NumberOfMissedRuns : 0
```
Two real reflection files exist on disk, confirmed via `ls`:
`logs/reflections/2026-07-07.md` (2750 bytes) and `logs/reflections/2026-07-08.md`
(534 bytes, file-timestamp `Jul 8 03:01` — fired on its FIRST scheduled attempt at
03:00 local, not after retries; the `LastRunTime: 6:00:01 AM` from Task Scheduler
appears to reflect the *last slot in the repetition window*, not a failed-then-retried
run — see §4 for why this matters and is not fully resolved).
- Script: `setup/create-reflection-scheduled-task.ps1` (7639 bytes, exists).
- Registered as the current user, `-LogonType Interactive` (deliberately not S4U — see
  the script's own comments for why: S4U needs admin elevation, Interactive doesn't and
  fits a laptop that stays logged in overnight).

### 1.8 `<think>`-block stripping fixed and verified in the real pipeline
- `intelligence/advisor.py:73` — `def _strip_thinking(text)`.
- `logs/reflections/2026-07-07.md` (written by a REAL scheduled run, not a test) contains
  clean markdown, zero `<think>` tags, zero code fences — read it yourself:
  `Get-Content logs\reflections\2026-07-07.md`.

### 1.9 All 6 decision sources genuinely logging, not just 4 claimed in code
```
$ python -c "
import json
sources=set()
with open('logs/decision_log.jsonl') as f:
    for line in f:
        sources.add(json.loads(line)['source'])
print(sorted(sources))
"
['admission', 'advisor', 'pool_flight', 'profitability', 'thermal', 'ucb1_bandit']
$ wc -l logs/decision_log.jsonl
174 logs/decision_log.jsonl
```
174 real, accumulated log lines. `logs/` is gitignored (`.gitignore:14`) — **this log
does NOT exist in a fresh clone of the repo**, only on this machine. Sprint 4's
Ryzanstein/sigma-telemetry work (§3) needs to run against THIS machine's log, or you
need a plan for how the log gets there.

### 1.10 Secrets hygiene
```
$ python -c "
import json
with open('config/config.json') as f:
    cfg = json.load(f)
print(repr(cfg.get('http', {}).get('access-token')))
"
'__API_TOKEN__'
```
The tracked config has a placeholder, not a live secret. The real token lives in a
DPAPI-adjacent file outside the repo (`%APPDATA%\XMRig\secure\api-token.txt`),
loaded via `dashboard/xmrig_api_client.py`'s `_load_api_token()`. Not re-verified in
this handoff session beyond confirming the tracked file is clean.

---

## 2. Done But Not Verified (in this handoff session)

Code exists and was verified during Phase 3 implementation, but **not re-executed just
now** to produce this document. Treat as "probably fine" not "confirmed."

- **Live "Ask the Miner" UI round-trip** (§1.6) — verified live during Phase 3 via
  accessibility-tree automation (typed question, clicked Ask, got real answer). Not
  re-clicked for this handoff.
- **Full duty-cycle pause/resume timing** — Phase 3 measured ~11s recovery for QUERY
  mode, ~5s for REFLECT mode resume. Not re-measured here; the scheduled task's success
  in §1.7 is indirect evidence the mechanism still works, not a direct timing measurement.
- **10-question zero-fabrication advisor audit** — ran and passed 10/10 during Phase 3.
  Not re-run for this handoff (each run takes several minutes of real duty-cycling
  against the live miner). Re-run with: `python -m intelligence.advisor --audit`
  (takes ~5-15 minutes, pauses/downshifts mining repeatedly while running).
- **`pool_flight_table.py` logging** — confirmed present in `logs/decision_log.jsonl`
  (§1.9 shows `pool_flight` in the source set), but I did not re-trigger a pool
  recommendation change just now to watch it fire live.

---

## 3. Planned, Not Started — This Is What You're Being Handed

**Sprint 4 (Sigma ecosystem federation)** — the original plan's exact text, verbatim
from `F:\Projects\XMRig\Local Intelligence Layer v2.txt` lines 391-411:

```
SPRINT 4 — Sigma ecosystem federation                (~4–6 h, OPTIONAL)
⚠ BLOCKED until S:\ drive is mounted (not attached at scan time).

4.1 @APEX Ryzanstein: embed nightly reflections + notable decision events
    into the vector store. Use a CPU embedding model (nomic-embed-text or
    all-minilm via Ollama) — embeddings are tiny; no GPU contention.
4.2 @SENTRY sigma-harvest: extend the existing Prometheus endpoint
    (dashboard/prometheus_metrics_server.py) with:
      inference_latency_seconds, inference_mode, advisor_calls_total,
      admission_queue_depth, hashrate_minutes_lost_total
4.3 @APEX sigma-telemetry: forward decision_log.jsonl as structured events
    (batch, not streaming — this is a laptop).
4.4 @SCRIBE Update global CLAUDE.md: correct XMRig path to
    F:\Projects\XMRig\xmrig-6.22.0\ and note this feature's existence.

DONE CRITERIA (Sprint 4)
  [ ] Telemetry visible in sigma-harvest without added mining lag
  [ ] Reflections retrievable from Ryzanstein by semantic query
  [ ] CLAUDE.md paths corrected
```

**None of 4.1-4.4 has any code written for it.** Zero.

### 3.1 Task 4.4 is based on a false premise — do not execute it as written

This is the single most important thing in this document. The plan tells you to
"correct XMRig path to `F:\Projects\XMRig\xmrig-6.22.0\`". **That path does not
contain an XMRig installation.** Verify this yourself right now:

```powershell
Test-Path 'F:\Projects\XMRig\xmrig-6.22.0\xmrig.exe'   # returns False
Test-Path 'C:\XMRig\xmrig-6.22.0\xmrig.exe'             # returns True
Get-Process xmrig | Select-Object Path                  # shows C:\XMRig\xmrig-6.22.0\xmrig.exe
```

`F:\Projects\XMRig\` only contains planning `.txt` documents (including the plan this
task came from). `C:\XMRig\xmrig-6.22.0\` is the real, live install — confirmed by the
running process's own path, right now, as you read this. The repo's own `CLAUDE.md`
already correctly says `C:\XMRig\xmrig-6.22.0\` (lines 28-29) and does **not** need
correcting. This false claim originated in the plan document itself (written by a
different AI session during Phase 3 setup) and was never fixed in the plan text, only
avoided in actual practice. If Task 4.4 is executed literally, it will break a correct
path reference. **Do not touch `CLAUDE.md`'s path lines unless you independently
re-verify which path is real first.**

### 3.2 What actually blocks Sprint 4, and what doesn't

- **Real blocker**: `S:\` is not mounted on this machine right now
  (`Test-Path S:\` → `False`, checked moments before writing this). Task 4.1's vector
  store and whatever `S:\`-hosted infrastructure Ryzanstein/sigma-harvest/sigma-telemetry
  depend on are presumably reachable via `S:\` or via the Debian box's own network path —
  **I do not know which**, and the original plan doesn't say either. This is a real
  open question, not something I have enough information to resolve for you.
- **Not actually blocking, just unstarted**: Task 4.2 (extending
  `dashboard/prometheus_metrics_server.py`) needs no `S:\` access at all — it's a
  self-contained code change to a file that already exists in this repo. It could be
  started immediately, independent of the `S:\` mount question.
- **Ambiguous dependency**: Task 4.3 ("forward decision_log.jsonl... batch, not
  streaming") doesn't specify a destination, format, or trigger mechanism (cron? manual?
  on nightly_reflect completion?). This needs a decision, not just implementation.

### 3.3 Decisions open — yours to make, not mine

I have enough information to make some calls here myself but deliberately haven't,
since Sprint 4 wasn't in scope for what I was asked to do (Sprint 3 completion only):

- **Whether `S:\` should be mounted for this at all**, versus reaching Ryzanstein/
  sigma-harvest over the network directly (they run on the Debian box at
  `192.168.1.170`, reachable via SSH per this ecosystem's existing conventions — `S:\`
  might not be the right integration path in the first place). I don't have enough
  context on why the original plan assumed `S:\` specifically.
- **Task 4.3's batch trigger and format** — needs a concrete decision before it's
  implementable, not just "batch, not streaming."
- **Whether to fix the plan document itself** (`F:\Projects\XMRig\Local Intelligence
  Layer v2.txt`) to remove the false Task 4.4 claim, versus leaving the historical
  document as-is and just not executing that line. I'd lean toward fixing it — leaving
  a known-false instruction sitting in an actionable plan is exactly the failure mode
  this whole project has already hit twice (see §5) — but this touches a file outside
  the repo and outside what I was asked to do this session, so I'm flagging it rather
  than just doing it.

---

## 4. Known Bugs, Limitations, TODOs

Ordered roughly by how much they matter, not by discovery order.

1. **CONFIRMED BUG, found while writing this handoff**: `nightly_reflect()`
   (`intelligence/advisor.py:236`) filters "today's" decision-log events using
   `datetime.now(timezone.utc).date().isoformat()` — a **UTC calendar date**. The
   scheduled task fires at 03:00 **local** time. This machine is US Eastern
   (`Get-TimeZone` → `Eastern Standard Time`, DST-observing, so UTC-4 in July). At
   03:00 local (07:00 UTC), the UTC calendar date has only been "today" for ~3 hours —
   so the filter captures roughly a 3-7 hour sliver of the quietest part of the night,
   not the prior 24 hours of real mining activity. **Live evidence**: the reflection
   that actually fired this morning (`logs/reflections/2026-07-08.md`, decision log
   entry `{"ts":"2026-07-08T07:01:28+00:00", ..., "detail":{"events_analyzed":0}}`)
   analyzed **zero events** and produced a content-free (though not broken — it degrades
   gracefully, doesn't crash or hallucinate) reflection. Suggested fix: use local date,
   or better, a rolling 24-hour window (`ts >= now - timedelta(hours=24)`) instead of a
   calendar-date string-prefix match, which would also fix it regardless of what
   timezone this ever runs in. **Not fixed as part of this handoff** — out of scope for
   what I was asked to do (write the handoff, not act on findings).
2. **Known limitation, flagged in code comments, not fixed**:
   `intelligence/admission.py:49` — `FULL_THREADS = [0, 2, 4, 6, 8, 10, 12, 14]` is a
   hardcoded constant. If the bandit (§1.4) ever determines a >8-thread arm is the best
   one and applies it, the next advisor query's duty-cycle restore will silently revert
   mining back to 8 threads afterward, since admission.py doesn't read the bandit's
   live best-arm. See the docstring on `intelligence/ucb1_bandit.py`'s `apply_hint()`
   for the full explanation. Not fixed — would require admission.py to read the
   bandit's state dynamically instead of using a constant.
3. **Task Scheduler `LastRunTime` discrepancy, not fully explained**: §1.7 shows
   `LastRunTime: 6:00:01 AM` even though the reflection file's own timestamp and the
   decision log both show the job actually completed at 03:01 local on its first
   attempt. My working theory is that Windows Task Scheduler's repetition metadata
   reports the *last scheduled slot in the repeat window* (03:00 + 3h retry window =
   06:00) rather than the first successful firing, especially since `nightly_reflect()`
   is deliberately idempotent so later firings in the window "succeed" trivially by
   returning the cached path. **I have not confirmed this theory** — it's a plausible
   explanation, not a verified one. Worth understanding fully before relying on
   `LastRunTime` as a health signal.
4. All of Sprint 4 (§3) — nothing built, several genuinely open decisions.
5. `.history/` directory bloat — pre-existing (VS Code local-history feature), never
   addressed, deliberately left alone during Phase 3 commits (see §5).
6. No feature branch was used for Phase 1-3 — everything is on `main` directly. If
   Phase 4 wants isolation, that's a fresh decision, not a continuation of an existing
   pattern.
7. Mining is currently running at a **measured net loss**: `intelligence/profitability.py`
   computed `reward_usd_day: -0.0168` (revenue $0.0754 vs power cost $0.0922) during
   Phase 3 testing, at 8 threads, $0.12/kWh assumed rate. Not re-measured for this
   handoff. This is a real, known economic fact about the underlying system Sprint 4
   would be adding telemetry/federation for — worth knowing before investing more
   engineering time into it.
8. `intelligence/pool_flight_table.py` found (during Phase 3, not re-verified here)
   that `supportxmr_ssl` scored higher (131ms latency) than the currently-configured
   `hashvault` pool — never acted on, no one asked to switch pools.

---

## 5. Assumptions and Uncertainties, Called Out Explicitly

- **I am assuming** the "ecosystem session" this document is handed to has SSH access
  to the Debian box (`192.168.1.170`) and read/write access to this Windows machine's
  filesystem (`C:\Users\sgbil\XMRig-Automation`, `F:\Projects\XMRig\`). If it's running
  in a sandboxed/remote context without access to either, most of Sprint 4 and even
  re-verifying this document's claims is not possible as written.
- **I am assuming** "Phase 4" in the request that produced this document means exactly
  "Sprint 4" as defined in `Local Intelligence Layer v2.txt` (Sigma ecosystem
  federation). If a different Phase 4 was meant, this entire §3 is the wrong target.
- **I do not know** why the original plan assumed `S:\`-drive access specifically for
  Ryzanstein/sigma-harvest/sigma-telemetry integration rather than direct network
  access to the Debian box. This may be a real architectural reason I'm unaware of, or
  it may be an assumption baked into the plan that's worth questioning.
- **I have not verified** that Ryzanstein, sigma-harvest, and sigma-telemetry are
  currently in a state ready to receive this integration (e.g., is Ryzanstein's vector
  store actually reachable and accepting writes right now? Does sigma-harvest's
  Prometheus endpoint have room for new metric names without collision?). A previous,
  unrelated session's ecosystem health check (not re-verified here, and not scoped to
  this repo) found sigma-watchdog inactive and load elevated on that box as of
  2026-07-07 — if that's still true, it may be worth checking before adding load via
  Sprint 4's integrations.
- **This document itself is uncommitted** (`PHASE4-HANDOFF.md`, written to the repo
  root, not yet `git add`ed). If the session reading this works from a fresh clone
  rather than this same machine, **this file does not exist there yet** — it needs to
  be committed and pushed first, and I did not do that as part of writing it, since I
  was asked for a handoff document, not asked to commit anything.

---

## 6. How to Re-Verify This Entire Document

Run in order, on this machine (`C:\Users\sgbil\XMRig-Automation`):

```powershell
# 1. Confirm git state matches §0
git log --oneline -10; git status; git branch --show-current; git tag -l

# 2. Confirm tests still pass
python -m pytest tests/ -v
python test-dashboard-logic.py

# 3. Confirm XMRig is still alive and which path it's really running from
Get-Process xmrig | Select-Object Id, StartTime, Path

# 4. Confirm the path claim in §3.1 yourself, don't take my word for it
Test-Path 'F:\Projects\XMRig\xmrig-6.22.0\xmrig.exe'   # expect False
Test-Path 'C:\XMRig\xmrig-6.22.0\xmrig.exe'             # expect True

# 5. Confirm the scheduled task and inspect the bug in §4.1 yourself
Get-ScheduledTask -TaskName "XMRig Nightly Reflection" | Get-ScheduledTaskInfo
Get-Content .\logs\reflections\2026-07-08.md    # should show "0 events recorded"

# 6. Confirm S:\ mount status (Sprint 4 blocker)
Test-Path 'S:\'

# 7. Read the original plan yourself — it's not in git
Get-Content 'F:\Projects\XMRig\Local Intelligence Layer v2.txt'
```

If any of these produce different output than what's documented above, **trust the
fresh output, not this document** — this is a snapshot from 2026-07-08, not a live feed.
