"""
XMRig MCP Server — Sigma Ecosystem Integration
================================================
Exposes XMRig mining telemetry and controls as MCP tools/resources
so any Sigma agent (@APEX, @ORACLE, @CIPHER, etc.) can query and
control the miner through mcp-mesh.

Tools:
  get_mining_status     — current hashrate, shares, uptime, algorithm
  get_earnings          — today/week earnings estimate (live XMR price)
  switch_coin           — switch active mining coin (XMR / RTM / VRSC)
  pause_mining          — pause miner N minutes
  resume_mining         — resume mining
  get_pool_status       — pool flight table recommendation
  get_optimal_threads   — UCB1 bandit recommendation
  run_monte_carlo       — earnings forecast with confidence intervals

Resources:
  mining://status       — live JSON status
  mining://earnings     — earnings projections

Usage:
  pip install mcp
  python xmrig_mcp_server.py
  (or register as MCP server in mcp-mesh config)
"""

import json
import os
import sys
import time

# Add parent dirs to path for sibling imports
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(_ROOT, 'dashboard'))
sys.path.insert(0, os.path.join(_ROOT, 'intelligence'))

try:
    from mcp.server.fastmcp import FastMCP
except ImportError:
    print("ERROR: 'mcp' package not installed. Run: pip install mcp")
    sys.exit(1)

from xmrig_api_client import get_client, XMRigAPIError

mcp = FastMCP("xmrig-mining")

XMRIG_PATH    = r"C:\XMRig"
CONFIGS_PATH  = os.path.join(XMRIG_PATH, "configs")
STATUS_FILE   = os.path.join(XMRIG_PATH, "logs", "profit-switcher-status.json")
POOL_STATUS   = os.path.join(XMRIG_PATH, "logs", "pool-flight-status.json")
BANDIT_STATE  = os.path.join(
    os.environ.get('APPDATA', os.path.expanduser('~')),
    'XMRig', 'bandit-state.json'
)


def _read_json(path: str) -> dict:
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


def _fetch_xmr_price() -> float:
    from monte_carlo import fetch_xmr_price
    return fetch_xmr_price()


# ============================================================================
# TOOLS
# ============================================================================

@mcp.tool()
def get_mining_status() -> dict:
    """Return current XMRig status: hashrate, shares, uptime, algorithm, pool."""
    client = get_client()
    try:
        summary = client.get_summary(use_cache=False)
        switcher = _read_json(STATUS_FILE)
        return {
            'running': True,
            'hashrate_10s': summary.hashrate_10s,
            'hashrate_60s': summary.hashrate_60s,
            'hashrate_15m': summary.hashrate_15m,
            'shares_accepted': summary.shares_accepted,
            'shares_rejected': summary.shares_rejected,
            'algorithm': summary.algorithm,
            'pool': summary.pool_url,
            'uptime_seconds': summary.uptime,
            'current_coin': switcher.get('CurrentCoin', 'XMR'),
            'version': summary.version,
            'source': 'api',
        }
    except XMRigAPIError:
        return {'running': False, 'error': 'XMRig API not responding'}


@mcp.tool()
def get_earnings(days: int = 1) -> dict:
    """
    Return earnings estimate for the given number of days.
    Uses live XMR price and current hashrate from XMRig API.
    """
    status = get_mining_status()
    hashrate = status.get('hashrate_60s', 0)
    price = _fetch_xmr_price()

    xmr_per_day = (hashrate / 1900) * 0.002
    usd_per_day = xmr_per_day * price

    return {
        'hashrate_hs': hashrate,
        'xmr_price_usd': price,
        'xmr_per_day': round(xmr_per_day, 6),
        'usd_per_day': round(usd_per_day, 4),
        'xmr_total': round(xmr_per_day * days, 6),
        'usd_total': round(usd_per_day * days, 4),
        'period_days': days,
    }


@mcp.tool()
def switch_coin(coin: str) -> dict:
    """
    Switch active mining coin. Supported: XMR, RTM, VRSC.
    Writes the appropriate config and restarts XMRig.
    """
    coin = coin.upper()
    coin_configs = {
        'XMR':  'config-xmr.json',
        'RTM':  'config-rtm.json',
        'VRSC': 'config-vrsc.json',
    }
    if coin not in coin_configs:
        return {'success': False, 'error': f"Unknown coin: {coin}. Valid: {list(coin_configs)}"}

    config_src = os.path.join(CONFIGS_PATH, coin_configs[coin])
    config_dst = os.path.join(XMRIG_PATH, 'xmrig-6.22.0', 'config.json')

    if not os.path.exists(config_src):
        return {'success': False, 'error': f"Config not found: {config_src}"}

    import shutil
    shutil.copy2(config_src, config_dst)
    return {
        'success': True,
        'coin': coin,
        'config_deployed': config_dst,
        'note': 'Restart XMRig to apply (or use pause/resume to trigger reload)',
    }


@mcp.tool()
def pause_mining() -> dict:
    """Pause XMRig mining via HTTP API."""
    client = get_client()
    try:
        ok = client.pause()
        return {'paused': ok}
    except XMRigAPIError as e:
        return {'paused': False, 'error': str(e)}


@mcp.tool()
def resume_mining() -> dict:
    """Resume XMRig mining via HTTP API."""
    client = get_client()
    try:
        ok = client.resume()
        return {'resumed': ok}
    except XMRigAPIError as e:
        return {'resumed': False, 'error': str(e)}


@mcp.tool()
def get_pool_status() -> dict:
    """Return pool flight table: latencies, scores, and recommended pool."""
    return _read_json(POOL_STATUS) or {
        'note': 'Pool flight table not running. Start: python intelligence/pool_flight_table.py --daemon'
    }


@mcp.tool()
def get_optimal_threads() -> dict:
    """Return UCB1 bandit recommendation for optimal thread count."""
    state = _read_json(BANDIT_STATE)
    if not state:
        return {
            'note': 'No bandit data yet. Run: python intelligence/ucb1_bandit.py --next',
            'current_hint': 50,
            'reason': 'Default: 50% (8 threads) fits Ryzen 7 7730U 16MB L3 exactly',
        }
    arms = state.get('arms', [])
    total = state.get('total_pulls', 0)
    if total < 3:
        return {
            'total_measurements': total,
            'note': f'Need more data. Run: python intelligence/ucb1_bandit.py --next',
        }
    best = max((a for a in arms if a['pulls'] > 0),
               key=lambda a: a['total_reward'] / a['pulls'], default=None)
    return {
        'total_measurements': total,
        'recommended_hint': best['hint'] if best else 50,
        'mean_hashrate': round(best['total_reward'] / best['pulls'], 1) if best else 0,
        'arms': arms,
    }


@mcp.tool()
def run_monte_carlo(hashrate: float = 1900.0, days: int = 7) -> dict:
    """
    Run Monte Carlo earnings forecast.
    Returns p5/p50/p95 USD estimates for the given period.
    """
    try:
        from monte_carlo import simulate_earnings, fetch_xmr_price
        price = fetch_xmr_price()
        result = simulate_earnings(hashrate, hashrate * 0.04, price, days, 10_000)
        return result
    except Exception as e:
        return {'error': str(e)}


# ============================================================================
# RESOURCES
# ============================================================================

@mcp.resource("mining://status")
def status_resource() -> str:
    """Live mining status as JSON."""
    return json.dumps(get_mining_status(), indent=2)


@mcp.resource("mining://earnings")
def earnings_resource() -> str:
    """Daily and weekly earnings projections."""
    return json.dumps({
        'daily':  get_earnings(1),
        'weekly': get_earnings(7),
    }, indent=2)


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == '__main__':
    print("Starting XMRig MCP Server...")
    print("Tools: get_mining_status, get_earnings, switch_coin, pause_mining,")
    print("       resume_mining, get_pool_status, get_optimal_threads, run_monte_carlo")
    print("Resources: mining://status, mining://earnings")
    mcp.run()
