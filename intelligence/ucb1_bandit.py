"""
UCB1 Thread-Count Bandit Optimizer
====================================
Multi-armed bandit using UCB1 to empirically discover the optimal
thread count for RandomX on the Ryzen 7 7730U (16MB L3, Zen 3+).

Arms: thread percentages mapped to approximate thread counts
  50% → 8 threads  (16MB scratchpad = exact L3 fit — expected winner)
  62% → 10 threads (20MB → slight thrash)
  75% → 12 threads (24MB → heavy thrash — current default)
  87% → 14 threads
  100% → 16 threads

Reward metric: net USD/day (XMR revenue minus modeled electricity cost,
see intelligence/profitability.py) — not raw H/s. This lets the bandit
legitimately discover that fewer threads, or not mining at all, is the
net-optimal choice on a 15W laptop.

State is persisted to JSON so the bandit survives reboots and continues
accumulating evidence across sessions.

Usage:
    python ucb1_bandit.py             # Show current recommendation
    python ucb1_bandit.py --auto              # Measure + record automatically (preferred)
    python ucb1_bandit.py --record 50 1950.0  # Manually record a raw-H/s result (legacy)
    python ucb1_bandit.py --apply             # Apply recommendation to config
"""

import json
import math
import os
import sys
import argparse
from dataclasses import dataclass, field, asdict
from typing import Optional

STATE_FILE = os.path.join(
    os.environ.get('APPDATA', os.path.expanduser('~')),
    'XMRig', 'bandit-state.json'
)
XMRIG_CONFIG = r"C:\XMRig\xmrig-6.22.0\config.json"
REPO_CONFIG   = r"C:\Users\sgbil\XMRig-Automation\config\config.json"

# Arms defined as (max-threads-hint %, approx threads on 16-thread CPU)
ARMS = [50, 62, 75, 87, 100]

# Physical cores are the even logical indices on this 8C/16T Zen3+ chip;
# odd indices are their SMT siblings. RandomX prefers physical cores
# (shared execution ports/cache make SMT siblings a net loss), so every
# arm fills physical cores first and only adds SMT siblings past 8 threads.
_PHYSICAL_CORES = [0, 2, 4, 6, 8, 10, 12, 14]
_SMT_SIBLINGS = [1, 3, 5, 7, 9, 11, 13, 15]


def _cores_for_hint(hint: int) -> list:
    """Map an arm's hint% to an explicit core list (see module docstring
    for the hint->thread-count table). This is what actually controls
    XMRig: cpu.rx (explicit list) takes priority over max-threads-hint
    whenever both are present."""
    threads = round(hint / 100 * 16)
    threads = max(1, min(16, threads))
    if threads <= 8:
        return _PHYSICAL_CORES[:threads]
    return _PHYSICAL_CORES + _SMT_SIBLINGS[:threads - 8]


def _log_decision(event: str, reason_code: str, detail: dict):
    """Best-effort structured decision logging (never breaks the bandit)."""
    try:
        from intelligence.decision_logger import DecisionLogger
        DecisionLogger().log(source="ucb1_bandit", event=event,
                             reason_code=reason_code, detail=detail)
    except Exception:
        pass


def _read_current_hint(config_path: str = XMRIG_CONFIG) -> Optional[int]:
    """Infer which arm XMRig is currently running as, from the REAL
    authoritative setting (cpu.rx's explicit core list), not the
    max-threads-hint field admission.py's duty-cycling has made stale.

    Returns None if cpu.rx's length doesn't match any known arm (e.g.
    mining is transiently in admission.py's 4-thread QUERY mode
    mid-duty-cycle) — the caller should skip recording in that case
    rather than attribute the measurement to the wrong arm.
    """
    try:
        with open(config_path) as f:
            rx = json.load(f)['cpu']['rx']
    except (OSError, KeyError, json.JSONDecodeError):
        return None
    threads = len(rx)
    for hint in ARMS:
        if round(hint / 100 * 16) == threads:
            return hint
    return None


def auto_record(state: 'BanditState') -> Optional[float]:
    """Measure live hashrate, compute power-aware reward, record it.

    Reward is XMR-revenue-usd/day minus electricity-cost/day (see
    intelligence/profitability.py) rather than raw H/s, so the bandit
    can legitimately discover that fewer threads (or not mining at all)
    is net-optimal. Returns the recorded reward, or None if the miner
    wasn't reachable.
    """
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from dashboard.xmrig_api_client import get_client
    from intelligence.profitability import power_aware_reward

    hint = _read_current_hint()
    if hint is None:
        print("Could not attribute current thread count to a known arm — "
              "config unreadable, or mining is transiently mid duty-cycle "
              "(e.g. admission.py's QUERY mode). Try again once settled "
              "back into a steady MINING-mode thread count.")
        return None

    client = get_client()  # auto-loads the secure API token
    try:
        hashrate = client.get_summary(use_cache=False).hashrate_10s
    except Exception as e:
        print(f"Could not reach XMRig API: {e}")
        return None
    if not hashrate:
        print("Miner reachable but reporting zero hashrate — not recording.")
        return None

    result = power_aware_reward(hashrate)
    state.record(hint, result['reward_usd_day'])
    print(f"Auto-recorded: hint={hint}%, hashrate={hashrate:.1f} H/s, "
          f"net reward=${result['reward_usd_day']:.4f}/day "
          f"({'profitable' if result['profitable'] else 'NET LOSS'})")
    return result['reward_usd_day']


# UCB1's exploration term sqrt(2 ln N / n) assumes rewards in [0,1]. Our
# rewards are net USD/day (roughly -0.06..+0.06 on a 15W laptop), so without
# normalization the exploration bonus (~2 early on) dwarfs the reward signal
# by ~30x and the bandit round-robins forever, never exploiting. Map the
# reward to [0,1] via a fixed plausible range before feeding it to UCB1's
# exploitation term. best_arm() still ranks by the RAW USD/day mean (that is
# the actual objective); only the explore/exploit balance uses the normalized
# value.
REWARD_MIN_USD_DAY = -0.10
REWARD_MAX_USD_DAY = 0.10


def _normalize_reward(usd_day: float) -> float:
    """Map a net-USD/day reward onto [0,1] for UCB1 (clamped)."""
    span = REWARD_MAX_USD_DAY - REWARD_MIN_USD_DAY
    norm = (usd_day - REWARD_MIN_USD_DAY) / span
    return max(0.0, min(1.0, norm))


@dataclass
class ArmState:
    hint: int          # max-threads-hint percentage
    pulls: int = 0
    total_reward: float = 0.0

    @property
    def mean(self) -> float:
        return self.total_reward / self.pulls if self.pulls > 0 else 0.0

    def ucb1(self, total_pulls: int) -> float:
        if self.pulls == 0:
            return float('inf')
        # Exploitation term normalized to [0,1] so it is on the same scale as
        # UCB1's exploration term (which assumes rewards in [0,1]). Without
        # this the USD/day mean (~0.02) is dwarfed ~30x by the bonus and the
        # bandit never exploits. best_arm() still ranks by the raw USD/day mean.
        return _normalize_reward(self.mean) + math.sqrt(2 * math.log(total_pulls) / self.pulls)


@dataclass
class BanditState:
    arms: list[ArmState] = field(default_factory=lambda: [ArmState(h) for h in ARMS])
    total_pulls: int = 0

    def select_arm(self) -> ArmState:
        """UCB1 arm selection."""
        return max(self.arms, key=lambda a: a.ucb1(max(self.total_pulls, 1)))

    def record(self, hint: int, reward: float):
        arm = next((a for a in self.arms if a.hint == hint), None)
        if arm is None:
            raise ValueError(f"Unknown hint: {hint}. Valid: {ARMS}")
        arm.pulls += 1
        arm.total_reward += reward
        self.total_pulls += 1
        _log_decision(
            event="reward_recorded", reason_code="UCB1_UPDATE",
            detail={"hint": hint, "reward": reward, "pulls": arm.pulls,
                    "mean": round(arm.mean, 4),
                    "total_pulls": self.total_pulls},
        )

    def best_arm(self) -> ArmState:
        """Arm with highest mean reward (exploitation only)."""
        tried = [a for a in self.arms if a.pulls > 0]
        return max(tried, key=lambda a: a.mean) if tried else self.arms[0]

    def save(self):
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, 'w') as f:
            json.dump({
                'total_pulls': self.total_pulls,
                'arms': [asdict(a) for a in self.arms],
            }, f, indent=2)

    @classmethod
    def load(cls) -> 'BanditState':
        if not os.path.exists(STATE_FILE):
            return cls()
        try:
            with open(STATE_FILE) as f:
                data = json.load(f)
            state = cls()
            state.total_pulls = data.get('total_pulls', 0)
            arm_map = {a['hint']: a for a in data.get('arms', [])}
            for arm in state.arms:
                if arm.hint in arm_map:
                    arm.pulls = arm_map[arm.hint]['pulls']
                    arm.total_reward = arm_map[arm.hint]['total_reward']
            return state
        except Exception:
            return cls()


def apply_hint(hint: int, config_path: str = XMRIG_CONFIG):
    """Apply an arm's thread count to XMRig config.

    Writes an explicit cpu.rx core list (see _cores_for_hint) — this is
    what XMRig actually obeys. max-threads-hint is also written for
    documentation, but XMRig ignores it whenever cpu.rx is an explicit
    list rather than null/auto, which it always is once admission.py's
    duty-cycling has touched the config.

    KNOWN LIMITATION: intelligence/admission.py's AdmissionController
    restores mining to its own hardcoded FULL_THREADS (8 cores) after
    every query/reflect duty cycle, regardless of what arm the bandit
    has applied here. If the bandit picks a >8-thread arm as best, the
    next advisor question will silently revert it to 8 threads. Not
    fixed here (would mean admission.py reading the bandit's live best
    arm instead of a constant) — flagged as a follow-up, out of scope
    for Sprint 3.
    """
    if not os.path.exists(config_path):
        print(f"Config not found: {config_path}")
        return False
    with open(config_path) as f:
        config = json.load(f)
    cores = _cores_for_hint(hint)
    config['cpu']['max-threads-hint'] = hint
    config['cpu']['rx'] = cores
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    _log_decision(
        event="hint_applied", reason_code="UCB1_APPLY",
        detail={"hint": hint, "cores": cores, "config": config_path},
    )
    print(f"Applied hint={hint}% -> {len(cores)} threads {cores} to {config_path}")
    return True


def print_status(state: BanditState):
    print("\n+--------------------------------------------------------+")
    print("|        UCB1 THREAD-COUNT BANDIT - STATUS               |")
    print("+--------------------------------------------------------+")
    print(f"  Total measurements: {state.total_pulls}")
    print()
    print(f"  {'Hint%':>6}  {'~Threads':>8}  {'Pulls':>6}  {'Mean $/day':>11}  {'UCB1':>11}")
    print(f"  {'------':>6}  {'--------':>8}  {'-----':>6}  {'-----------':>11}  {'-----------':>11}")
    for arm in state.arms:
        approx_threads = round(arm.hint / 100 * 16)
        ucb = arm.ucb1(max(state.total_pulls, 1))
        ucb_str = f"{ucb:.4f}" if ucb != float('inf') else "  (unexplored)"
        mean_str = f"{arm.mean:.4f}" if arm.pulls > 0 else "  -"
        print(f"  {arm.hint:>6}  {approx_threads:>8}  {arm.pulls:>6}  {mean_str:>11}  {ucb_str:>11}")

    next_arm = state.select_arm()
    print(f"\n  Next explore: hint={next_arm.hint}% (~{round(next_arm.hint/100*16)} threads)")

    if state.total_pulls >= 3:
        best = state.best_arm()
        print(f"  Best so far:  hint={best.hint}% (~{round(best.hint/100*16)} threads) "
              f"@ ${best.mean:.4f}/day avg net reward")
    print()


def main():
    parser = argparse.ArgumentParser(description="UCB1 Thread-Count Bandit")
    parser.add_argument('--record', nargs=2, metavar=('HINT', 'HASHRATE'),
                        help="Record a raw-hashrate result: --record 50 1950.0 "
                             "(legacy; prefer --auto for power-aware reward)")
    parser.add_argument('--auto', action='store_true',
                        help="Measure live hashrate + compute power-aware "
                             "USD/day reward automatically, then record it")
    parser.add_argument('--apply', action='store_true',
                        help="Apply the current best recommendation to config")
    parser.add_argument('--next', action='store_true',
                        help="Apply the next exploration arm")
    args = parser.parse_args()

    state = BanditState.load()

    if args.record:
        hint = int(args.record[0])
        reward = float(args.record[1])
        state.record(hint, reward)
        state.save()
        print(f"Recorded: hint={hint}%, hashrate={reward:.1f} H/s")

    elif args.auto:
        if auto_record(state) is not None:
            state.save()

    elif args.apply:
        if state.total_pulls < 3:
            print("Need at least 3 measurements before applying recommendation.")
            print("Run with --next to start exploring.")
        else:
            best = state.best_arm()
            apply_hint(best.hint)
            apply_hint(best.hint, REPO_CONFIG)

    elif args.next:
        next_arm = state.select_arm()
        print(f"Applying exploration arm: hint={next_arm.hint}% "
              f"(~{round(next_arm.hint/100*16)} threads)")
        apply_hint(next_arm.hint)

    print_status(state)


if __name__ == '__main__':
    main()
