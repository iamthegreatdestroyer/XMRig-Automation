"""
Monte Carlo Earnings Forecaster
=================================
Simulates N earnings scenarios by sampling from:
  - Hashrate distribution   (Gaussian fitted to observed mean/std)
  - Network difficulty walk (Geometric Brownian Motion, weekly drift)
  - XMR price volatility    (log-normal, historical ~4% daily vol)

Returns 5th / 50th / 95th percentile estimates for daily and weekly earnings.

Usage:
    python monte_carlo.py                          # use defaults
    python monte_carlo.py --hashrate 1950 --days 7
    python monte_carlo.py --hashrate 1950 --std 80 --days 30 --sims 50000
"""

import argparse
import math
import random
import json
import os
import time

# XMR network parameters (approximations for 2026)
XMR_BLOCK_REWARD   = 0.6        # XMR per block (tail emission era)
XMR_BLOCKS_PER_DAY = 720        # ~2-min block time

# Difficulty GBM parameters (annualised from 2024-2026 data)
DIFF_DAILY_DRIFT   = 0.0003     # slight upward trend
DIFF_DAILY_VOL     = 0.025      # daily volatility

# Price log-normal parameters
PRICE_DAILY_VOL    = 0.04       # ~4% daily volatility (XMR historical)
PRICE_DAILY_DRIFT  = -0.0001    # slight mean-reversion assumption

# Network hashrate proxy (used to normalise your share)
NETWORK_HASHRATE_GHS = 3.2e9    # ~3.2 GH/s


def simulate_earnings(
    hashrate_hs: float,
    hashrate_std: float,
    xmr_price_usd: float,
    days: int = 7,
    n_sim: int = 20_000,
) -> dict:
    """Run Monte Carlo simulation. Returns percentile dict."""
    total_earnings_usd = []

    for _ in range(n_sim):
        # Sample constant-ish hashrate for this scenario (Gaussian)
        h = max(1, random.gauss(hashrate_hs, hashrate_std))

        cumulative_usd = 0.0
        price = xmr_price_usd
        network_diff = NETWORK_HASHRATE_GHS  # proxy for difficulty

        for _ in range(days):
            # Update difficulty via GBM
            z_d = random.gauss(0, 1)
            network_diff *= math.exp(
                (DIFF_DAILY_DRIFT - 0.5 * DIFF_DAILY_VOL**2)
                + DIFF_DAILY_VOL * z_d
            )

            # Update price via log-normal
            z_p = random.gauss(0, 1)
            price *= math.exp(
                (PRICE_DAILY_DRIFT - 0.5 * PRICE_DAILY_VOL**2)
                + PRICE_DAILY_VOL * z_p
            )

            # Your share of blocks (proportional to hashrate)
            share = h / network_diff
            daily_xmr = share * XMR_BLOCK_REWARD * XMR_BLOCKS_PER_DAY
            cumulative_usd += daily_xmr * price

        total_earnings_usd.append(cumulative_usd)

    total_earnings_usd.sort()
    n = len(total_earnings_usd)

    def pct(p):
        idx = int(p / 100 * n)
        return round(total_earnings_usd[min(idx, n - 1)], 4)

    return {
        'period_days': days,
        'simulations': n_sim,
        'hashrate_hs': hashrate_hs,
        'hashrate_std': hashrate_std,
        'xmr_price_usd': xmr_price_usd,
        'p5_usd':  pct(5),
        'p50_usd': pct(50),
        'p95_usd': pct(95),
        'daily_p5':  round(pct(5)  / days, 4),
        'daily_p50': round(pct(50) / days, 4),
        'daily_p95': round(pct(95) / days, 4),
    }


def fetch_xmr_price() -> float:
    """Live XMR/USD from CoinGecko with 5-min cache."""
    cache_file = os.path.join(
        os.environ.get('APPDATA', os.path.expanduser('~')),
        'XMRig', 'xmr-price-cache.json'
    )
    try:
        if os.path.exists(cache_file):
            with open(cache_file) as f:
                c = json.load(f)
            if time.time() - c.get('ts', 0) < 300:
                return c['price']
    except Exception:
        pass

    try:
        from urllib.request import urlopen
        with urlopen(
            "https://api.coingecko.com/api/v3/simple/price?ids=monero&vs_currencies=usd",
            timeout=5
        ) as r:
            price = float(json.loads(r.read())['monero']['usd'])
        os.makedirs(os.path.dirname(cache_file), exist_ok=True)
        with open(cache_file, 'w') as f:
            json.dump({'price': price, 'ts': time.time()}, f)
        return price
    except Exception:
        return 322.66  # fallback


def main():
    parser = argparse.ArgumentParser(description="Monte Carlo Earnings Forecaster")
    parser.add_argument('--hashrate', type=float, default=1900.0, help="Mean hashrate H/s")
    parser.add_argument('--std', type=float, default=80.0, help="Hashrate std dev H/s")
    parser.add_argument('--days', type=int, default=7, help="Forecast horizon (days)")
    parser.add_argument('--sims', type=int, default=20000, help="Number of simulations")
    parser.add_argument('--price', type=float, default=None, help="XMR price USD (fetches live if omitted)")
    args = parser.parse_args()

    price = args.price or fetch_xmr_price()
    print(f"\n  XMR price: ${price:.2f}")
    print(f"  Hashrate:  {args.hashrate:.0f} ± {args.std:.0f} H/s")
    print(f"  Horizon:   {args.days} days  |  Simulations: {args.sims:,}")
    print("\n  Running Monte Carlo...")

    result = simulate_earnings(args.hashrate, args.std, price, args.days, args.sims)

    print("\n+--------------------------------------------------+")
    print("|         EARNINGS FORECAST (Monte Carlo)          |")
    print("+--------------------------------------------------+")
    print(f"  Period: {result['period_days']} days\n")
    print(f"  {'Scenario':<16}  {'Daily':>10}  {'Total ({} days)'.format(args.days):>16}")
    print(f"  {'--------':<16}  {'-----':>10}  {'-----':>16}")
    print(f"  {'Pessimistic (5%)':<16}  ${result['daily_p5']:>9.2f}  ${result['p5_usd']:>15.2f}")
    print(f"  {'Median (50%)':<16}  ${result['daily_p50']:>9.2f}  ${result['p50_usd']:>15.2f}")
    print(f"  {'Optimistic (95%)':<16}  ${result['daily_p95']:>9.2f}  ${result['p95_usd']:>15.2f}")
    spread = result['p95_usd'] - result['p5_usd']
    print(f"\n  90% confidence interval width: ${spread:.2f}")
    print()


if __name__ == '__main__':
    main()
