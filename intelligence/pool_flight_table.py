"""
Pool Flight Table — Dynamic latency-aware pool routing for XMR
================================================================
Maintains a live "flight table" of 6 XMR-compatible pools with
real-time TCP latency probes, stale-job detection, and rejection
rate tracking. Writes the optimal pool to a status file consumed
by the profit switcher and dashboard.

Run as background service:
    python pool_flight_table.py --daemon

Or query current recommendation:
    python pool_flight_table.py --recommend

Status file: C:\\XMRig\\logs\\pool-flight-status.json
"""

import json
import os
import socket
import threading
import time
import argparse
from dataclasses import dataclass, field, asdict
from typing import Optional

STATUS_FILE  = r"C:\XMRig\logs\pool-flight-status.json"
PROBE_INTERVAL = 120    # seconds between full probes
STALE_JOB_THRESHOLD = 45  # seconds without a new job = stale

XMR_POOLS = {
    "hashvault_ssl":  ("pool.hashvault.pro",    443,  True,  1.0),
    "hashvault_tcp":  ("pool.hashvault.pro",    3333, False, 1.0),
    "supportxmr_ssl": ("pool.supportxmr.com",   443,  True,  0.6),
    "xmrpool_eu":     ("xmrpool.eu",            5555, True,  0.4),
    "nanopool_eu":    ("xmr-eu1.nanopool.org",  14433,True,  0.4),
    "minexmr_de":     ("de.minexmr.com",        443,  True,  0.3),
}


@dataclass
class PoolEntry:
    key: str
    host: str
    port: int
    tls: bool
    fee_percent: float
    latency_ms: float = 9999.0
    last_probe: float = 0.0
    failures: int = 0
    consecutive_failures: int = 0
    accepted: int = 0
    rejected: int = 0

    @property
    def score(self) -> float:
        """Lower latency + lower rejection rate + lower fee = higher score."""
        if self.consecutive_failures >= 3:
            return -9999.0
        rejection_rate = self.rejected / max(self.accepted + self.rejected, 1)
        # Normalize: target latency 20ms, max 500ms
        latency_score = max(0, 1 - (self.latency_ms / 500))
        quality_score = 1 - rejection_rate
        fee_score = 1 - (self.fee_percent / 2.0)
        return latency_score * 0.5 + quality_score * 0.35 + fee_score * 0.15

    def pool_url(self) -> str:
        proto = "stratum+ssl" if self.tls else "stratum+tcp"
        return f"{proto}://{self.host}:{self.port}"


class PoolFlightTable:
    def __init__(self):
        self.pools: dict[str, PoolEntry] = {
            k: PoolEntry(k, h, p, tls, fee)
            for k, (h, p, tls, fee) in XMR_POOLS.items()
        }
        self._lock = threading.Lock()
        self._running = False

    def probe_all(self):
        """TCP-connect probe all pools in parallel."""
        threads = [
            threading.Thread(target=self._probe, args=(entry,), daemon=True)
            for entry in self.pools.values()
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

    def _probe(self, entry: PoolEntry):
        start = time.monotonic()
        try:
            with socket.create_connection((entry.host, entry.port), timeout=8):
                pass
            latency = (time.monotonic() - start) * 1000
            with self._lock:
                entry.latency_ms = round(latency, 2)
                entry.last_probe = time.time()
                entry.consecutive_failures = 0
        except Exception:
            with self._lock:
                entry.latency_ms = 9999.0
                entry.failures += 1
                entry.consecutive_failures += 1

    def best_pool(self) -> Optional[PoolEntry]:
        with self._lock:
            active = [p for p in self.pools.values() if p.consecutive_failures < 3]
            if not active:
                return None
            return max(active, key=lambda p: p.score)

    def record_share(self, pool_key: str, accepted: bool):
        with self._lock:
            if pool_key in self.pools:
                if accepted:
                    self.pools[pool_key].accepted += 1
                else:
                    self.pools[pool_key].rejected += 1

    def write_status(self):
        best = self.best_pool()
        os.makedirs(os.path.dirname(STATUS_FILE), exist_ok=True)
        # Decision-log recommendation changes (best-effort, never fatal)
        if best and getattr(self, "_last_recommended", None) != best.key:
            try:
                from intelligence.decision_logger import DecisionLogger
                DecisionLogger().log(
                    source="pool_flight", event="recommendation_changed",
                    reason_code="LATENCY_SCORE",
                    detail={"pool": best.key, "url": best.pool_url(),
                            "latency_ms": best.latency_ms,
                            "score": round(best.score, 4)},
                    state_before={"pool": getattr(self, "_last_recommended", None)},
                    state_after={"pool": best.key},
                )
            except Exception:
                pass
            self._last_recommended = best.key
        status = {
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
            'recommended_pool': best.pool_url() if best else None,
            'recommended_key': best.key if best else None,
            'pools': [
                {
                    'key': p.key,
                    'url': p.pool_url(),
                    'latency_ms': p.latency_ms,
                    'score': round(p.score, 4),
                    'consecutive_failures': p.consecutive_failures,
                    'rejection_rate': round(
                        p.rejected / max(p.accepted + p.rejected, 1), 4
                    ),
                }
                for p in sorted(self.pools.values(), key=lambda x: -x.score)
            ]
        }
        with open(STATUS_FILE, 'w') as f:
            json.dump(status, f, indent=2)

    def run_daemon(self):
        """Background service loop."""
        self._running = True
        print("Pool Flight Table daemon started.")
        while self._running:
            print(f"[{time.strftime('%H:%M:%S')}] Probing {len(self.pools)} pools...")
            self.probe_all()
            self.write_status()
            best = self.best_pool()
            if best:
                print(f"  Best pool: {best.key} @ {best.latency_ms:.1f}ms "
                      f"(score: {best.score:.3f})")
            time.sleep(PROBE_INTERVAL)

    def print_table(self):
        print("\n+------------------------------------------------------------+")
        print("|              POOL FLIGHT TABLE                             |")
        print("+------------------------------------------------------------+")
        print(f"  {'Pool Key':20}  {'Latency':>10}  {'Score':>8}  {'Failures':>8}")
        print(f"  {'--------':20}  {'-------':>10}  {'-----':>8}  {'--------':>8}")
        for p in sorted(self.pools.values(), key=lambda x: -x.score):
            lat = f"{p.latency_ms:.1f}ms" if p.latency_ms < 9000 else "UNREACHABLE"
            print(f"  {p.key:20}  {lat:>10}  {p.score:>8.4f}  {p.consecutive_failures:>8}")
        best = self.best_pool()
        if best:
            print(f"\n  Recommended: {best.pool_url()}")
        print()


def main():
    parser = argparse.ArgumentParser(description="Pool Flight Table")
    parser.add_argument('--daemon', action='store_true', help="Run as background service")
    parser.add_argument('--recommend', action='store_true', help="Probe and show recommendation")
    args = parser.parse_args()

    table = PoolFlightTable()

    if args.daemon:
        table.run_daemon()
    else:
        print("Probing pools (this takes ~10 seconds)...")
        table.probe_all()
        table.write_status()
        table.print_table()


if __name__ == '__main__':
    main()
