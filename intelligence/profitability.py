"""
Power-Aware Profitability
=========================
Computes the bandit reward as NET profit: XMR earned/day (USD) minus
electricity cost/day (USD). This lets the UCB1 bandit legitimately
discover that fewer threads — or not mining at all — may be net-optimal
on a 15W laptop.

    reward_usd_day = daily_xmr_usd(hashrate) - (watts/1000 * 24 * rate)

Live-validated constants (HashVault dashboard, 2026-07-06): at ~1.38 kH/s
the pool estimated ~0.000022 XMR/day early-session; steady-state yield is
computed from the network-share model in monte_carlo.py.

Usage:
    python -m intelligence.profitability --hashrate 1342
    python -m intelligence.profitability --hashrate 1342 --watts 32 --rate 0.12

Author: XMRig Automation
License: MIT
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from intelligence.monte_carlo import (  # noqa: E402
    fetch_xmr_price, XMR_BLOCK_REWARD, XMR_BLOCKS_PER_DAY,
    NETWORK_HASHRATE_GHS,
)
from intelligence.decision_logger import DecisionLogger  # noqa: E402

# System wall-power estimate while mining 8 threads on the 7730U
# (package ~25W + platform overhead). Override with --watts or env.
DEFAULT_SYSTEM_WATTS = float(os.environ.get("MINING_SYSTEM_WATTS", 32.0))
DEFAULT_RATE_USD_KWH = float(os.environ.get("ELECTRICITY_RATE_USD_KWH", 0.12))


def daily_xmr(hashrate_hs: float) -> float:
    """Expected XMR/day at given hashrate (network-share model)."""
    share = hashrate_hs / NETWORK_HASHRATE_GHS
    return share * XMR_BLOCK_REWARD * XMR_BLOCKS_PER_DAY


def power_aware_reward(
    hashrate_hs: float,
    system_watts: float = DEFAULT_SYSTEM_WATTS,
    rate_usd_kwh: float = DEFAULT_RATE_USD_KWH,
    xmr_price_usd: float = None,
    log: bool = True,
) -> dict:
    """Net USD/day profit. Use result['reward_usd_day'] as bandit reward."""
    price = xmr_price_usd if xmr_price_usd is not None else fetch_xmr_price()
    xmr_day = daily_xmr(hashrate_hs)
    revenue = xmr_day * price
    power_cost = system_watts / 1000.0 * 24.0 * rate_usd_kwh
    reward = revenue - power_cost

    result = {
        "hashrate_hs": hashrate_hs,
        "xmr_per_day": round(xmr_day, 8),
        "xmr_price_usd": round(price, 2),
        "revenue_usd_day": round(revenue, 4),
        "power_watts": system_watts,
        "power_cost_usd_day": round(power_cost, 4),
        "reward_usd_day": round(reward, 4),
        "profitable": reward > 0,
    }

    if log:
        DecisionLogger().log(
            source="profitability",
            event="daily_reward_computed",
            reason_code="NET_PROFIT" if reward > 0 else "NET_LOSS",
            detail=result,
        )
    return result


def main():
    parser = argparse.ArgumentParser(description="Power-aware profitability")
    parser.add_argument("--hashrate", type=float, required=True)
    parser.add_argument("--watts", type=float, default=DEFAULT_SYSTEM_WATTS)
    parser.add_argument("--rate", type=float, default=DEFAULT_RATE_USD_KWH)
    parser.add_argument("--price", type=float, default=None)
    args = parser.parse_args()

    r = power_aware_reward(args.hashrate, args.watts, args.rate, args.price)
    print(f"\n  Hashrate:        {r['hashrate_hs']:.0f} H/s")
    print(f"  XMR/day:         {r['xmr_per_day']:.8f}")
    print(f"  XMR price:       ${r['xmr_price_usd']:.2f}")
    print(f"  Revenue/day:     ${r['revenue_usd_day']:.4f}")
    print(f"  Power cost/day:  ${r['power_cost_usd_day']:.4f}  ({r['power_watts']}W @ ${args.rate}/kWh)")
    print(f"  NET reward/day:  ${r['reward_usd_day']:.4f}  "
          f"{'PROFITABLE' if r['profitable'] else 'NET LOSS'}\n")


if __name__ == "__main__":
    main()
