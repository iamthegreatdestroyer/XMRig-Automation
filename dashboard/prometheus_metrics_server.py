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

        # Update initial metrics
        metrics.hashrate.labels(algorithm="rx/0").set(0)
        metrics.cpu_temp.set(25.0)
        metrics.shares_accepted.inc(0)
        metrics.shares_rejected.inc(0)
        metrics.pool_latency.labels(pool="unknown").set(0)
        metrics.health_score.set(100)
        metrics.record_mode("MINING")

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

    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")
        raise

if __name__ == "__main__":
    main()
