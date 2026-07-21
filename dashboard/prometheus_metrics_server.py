#!/usr/bin/env python3
"""
XMRig Automation - Production Prometheus Metrics Server
=======================================================
Production-ready metrics server that runs continuously.

Sprint 4.2 (Sigma ecosystem federation): tails logs/decision_log.jsonl to
keep the Local Intelligence Layer metrics (inference_latency_seconds,
inference_mode, advisor_calls_total, hashrate_minutes_lost_total) current
across process boundaries. Each `--ask`/`--reflect` CLI invocation is its
own short-lived process with its own in-memory metrics state that dies
when it exits -- decision_log.jsonl is the one thing that actually
persists across those invocations, so THIS long-running server derives
the metrics from it rather than depending on any other process to push
into it directly. (admission_queue_depth is intentionally NOT derived
here -- it reflects a single process's live in-memory queue and isn't
meaningfully reconstructable from history; it will read 0 from this
server and only reflects real values when observed within the same
process that queued a job, which today only happens via a direct
in-process caller such as the test harness.)

Author: XMRig Automation
License: MIT
"""

import json
import logging
import os
import time
import urllib.error
import urllib.request

from prometheus_metrics import start_metrics_server

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

DECISION_LOG_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "logs", "decision_log.jsonl",
)
TAIL_POLL_INTERVAL_S = 10

# xmrig's own local HTTP API (host/port/access-token) is the real source
# of truth for hashrate/shares/pool latency. Previously this server only
# ever set those metrics once at startup to hardcoded placeholder values
# and never touched them again -- this reads the real numbers from xmrig
# itself on the same poll cadence as the decision-log tail.
#
# NOTE: this reads XMRig's RUNTIME config, not the repo's config/config.json
# template -- production-start.ps1 injects the real DPAPI-decrypted
# access-token into C:\XMRig\xmrig-6.22.0\config.json at startup; the repo
# template only ever holds the "__API_TOKEN__" placeholder.
XMRIG_CONFIG_PATH = r"C:\XMRig\xmrig-6.22.0\config.json"


def _load_xmrig_api():
    """Read xmrig's own HTTP API host/port/token from its config.json so
    the token isn't duplicated/hardcoded here."""
    try:
        with open(XMRIG_CONFIG_PATH, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        http_cfg = cfg.get("http", {})
        if not http_cfg.get("enabled"):
            return None
        host = http_cfg.get("host", "127.0.0.1")
        port = http_cfg.get("port", 16000)
        token = http_cfg.get("access-token")
        return "http://%s:%d" % (host, port), token
    except (OSError, ValueError, TypeError, AttributeError):
        # Fail soft on ANY malformed config (missing file, bad JSON, a
        # non-int/None "port" that would make "%d" raise TypeError, or a
        # non-dict shape that makes .get raise AttributeError) so a bad
        # config can never crash the long-lived metrics server loop.
        return None


def _poll_xmrig(metrics, last_shares):
    """Pull real stats from xmrig's own API and push them into the
    metrics that were previously frozen at hardcoded init values. Returns
    the (accepted, rejected) totals seen this poll, for delta-tracking on
    the next call (xmrig's API reports cumulative totals; the Prometheus
    counters need increments)."""
    api = _load_xmrig_api()
    if not api:
        return last_shares
    base_url, token = api
    if not token:
        return last_shares
    req = urllib.request.Request(
        base_url + "/2/summary",
        headers={"Authorization": "Bearer " + token},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            summary = json.load(r)
    except (urllib.error.URLError, OSError, ValueError) as e:
        logger.warning(f"xmrig API poll failed (continuing): {e}")
        return last_shares

    hr = (summary.get("hashrate") or {}).get("total", [None])[0]
    if isinstance(hr, (int, float)):
        metrics.hashrate.labels(algorithm=summary.get("algo", "rx/0")).set(hr)

    conn = summary.get("connection") or {}
    ping = conn.get("ping")
    pool = conn.get("pool") or "unknown"
    if isinstance(ping, (int, float)):
        metrics.pool_latency.labels(pool=pool).set(ping)

    prev_accepted, prev_rejected = last_shares
    accepted = conn.get("accepted", prev_accepted)
    rejected = conn.get("rejected", prev_rejected)
    if accepted >= prev_accepted:
        metrics.shares_accepted.inc(accepted - prev_accepted)
    if rejected >= prev_rejected:
        metrics.shares_rejected.inc(rejected - prev_rejected)

    # Real-signal health proxy -- xmrig's API exposes no hardware
    # thermal/voltage data, so this isn't a literal sensor reading. It
    # reflects connectivity + active hashing + a low reject ratio, which
    # is the closest honest substitute available from this API.
    total = accepted + rejected
    reject_ratio = (rejected / total) if total else 0.0
    connected = bool(conn.get("pool")) and not summary.get("paused", True)
    if connected and hr and reject_ratio < 0.05:
        metrics.health_score.set(100.0)
    elif connected:
        metrics.health_score.set(50.0)
    else:
        metrics.health_score.set(0.0)

    return (accepted, rejected)


def _tail_new_lines(path: str, offset: int) -> tuple:
    """Read any lines appended to `path` since `offset`. Returns
    (new_offset, list_of_parsed_records). Malformed lines are skipped,
    not fatal -- this is best-effort observability, not the source of
    truth (the log file itself remains that)."""
    if not os.path.exists(path):
        return offset, []
    records = []
    with open(path, "r", encoding="utf-8") as f:
        f.seek(offset)
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        new_offset = f.tell()
    return new_offset, records


def _apply_record(metrics, record: dict) -> None:
    """Update Sprint 4.2 metrics from one decision-log record. Silently
    ignores records it doesn't recognize -- this log carries many event
    types from other subsystems (bandit, thermal, pool_flight) that
    aren't relevant to these particular metrics."""
    event = record.get("event")
    detail = record.get("detail") or {}

    if event == "inference_complete":
        inference_s = detail.get("inference_s")
        if isinstance(inference_s, (int, float)):
            metrics.inference_latency.set(inference_s)
            metrics.advisor_calls.inc()
            if detail.get("mining_active"):
                recovery_s = detail.get("recovery_s") or 0.0
                metrics.hashrate_minutes_lost.inc(
                    (inference_s + recovery_s) / 60.0
                )
    elif event == "mode_change":
        state_after = record.get("state_after") or {}
        mode = state_after.get("mode")
        if mode:
            metrics.record_mode(mode)


def main():
    """Main production server function."""
    logger.info("Starting XMRig Prometheus Metrics Server (Production)")

    try:
        # Start the metrics server
        metrics = start_metrics_server(port=29100)
        logger.info("Metrics server started on port 29100")

        # Register the share counters at 0 so they appear in /metrics
        # immediately; real values (and everything else here) come from
        # the first xmrig API poll below, not a hardcoded guess.
        metrics.shares_accepted.inc(0)
        metrics.shares_rejected.inc(0)
        metrics.record_mode("MINING")

        # cpu_temp intentionally NOT set here -- xmrig's own API exposes
        # no thermal data, and this server has no other real source for
        # it. Better to leave it absent from /metrics (renders "n/a" on
        # the dashboard) than keep faking a frozen 25.0C reading.

        last_shares = (0, 0)
        last_shares = _poll_xmrig(metrics, last_shares)

        # Start tailing decision_log.jsonl from its current end -- only
        # events from this point forward are counted. This is standard
        # Prometheus counter semantics (counters reset on process
        # restart; consumers use rate()/increase() to handle that), not
        # an attempt to replay all history.
        offset = os.path.getsize(DECISION_LOG_PATH) \
            if os.path.exists(DECISION_LOG_PATH) else 0
        logger.info(f"Tailing {DECISION_LOG_PATH} from offset {offset}")

        logger.info("Initial metrics set")

        # Keep the server running
        logger.info("Server running continuously. Press Ctrl+C to stop.")
        while True:
            time.sleep(TAIL_POLL_INTERVAL_S)
            try:
                offset, records = _tail_new_lines(DECISION_LOG_PATH, offset)
                for record in records:
                    _apply_record(metrics, record)
            except Exception as e:  # noqa: BLE001
                # A tailing hiccup must never crash the metrics server.
                logger.warning(f"decision_log tail error (continuing): {e}")

            last_shares = _poll_xmrig(metrics, last_shares)

    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")
        raise

if __name__ == "__main__":
    main()
