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

Reward metric: H/s per watt (if smart plug unavailable, uses H/s alone).

State is persisted to JSON so the bandit survives reboots and continues
accumulating evidence across sessions.

Usage:
    python ucb1_bandit.py             # Show current recommendation
    python ucb1_bandit.py --record 8 1950.0  # Record a measurement
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
        return self.mean + math.sqrt(2 * math.log(total_pulls) / self.pulls)


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
    """Write max-threads-hint to XMRig config."""
    if not os.path.exists(config_path):
        print(f"Config not found: {config_path}")
        return False
    with open(config_path) as f:
        config = json.load(f)
    config['cpu']['max-threads-hint'] = hint
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"Applied max-threads-hint: {hint}% to {config_path}")
    return True


def print_status(state: BanditState):
    print("\n+--------------------------------------------------------+")
    print("|        UCB1 THREAD-COUNT BANDIT - STATUS               |")
    print("+--------------------------------------------------------+")
    print(f"  Total measurements: {state.total_pulls}")
    print()
    print(f"  {'Hint%':>6}  {'~Threads':>8}  {'Pulls':>6}  {'Mean H/s':>10}  {'UCB1':>10}")
    print(f"  {'------':>6}  {'--------':>8}  {'-----':>6}  {'--------':>10}  {'----':>10}")
    for arm in state.arms:
        approx_threads = round(arm.hint / 100 * 16)
        ucb = arm.ucb1(max(state.total_pulls, 1))
        ucb_str = f"{ucb:.2f}" if ucb != float('inf') else "  (unexplored)"
        mean_str = f"{arm.mean:.1f}" if arm.pulls > 0 else "  -"
        print(f"  {arm.hint:>6}  {approx_threads:>8}  {arm.pulls:>6}  {mean_str:>10}  {ucb_str:>10}")

    next_arm = state.select_arm()
    print(f"\n  Next explore: hint={next_arm.hint}% (~{round(next_arm.hint/100*16)} threads)")

    if state.total_pulls >= 3:
        best = state.best_arm()
        print(f"  Best so far:  hint={best.hint}% (~{round(best.hint/100*16)} threads) "
              f"@ {best.mean:.1f} H/s avg")
    print()


def main():
    parser = argparse.ArgumentParser(description="UCB1 Thread-Count Bandit")
    parser.add_argument('--record', nargs=2, metavar=('HINT', 'HASHRATE'),
                        help="Record result: --record 50 1950.0")
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
