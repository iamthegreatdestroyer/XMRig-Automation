"""
Decision Logger
===============
Append-only structured JSONL log of every decision made by the
intelligence layer. This log is the LLM advisor's ground truth:
every advisor answer must cite reason_codes present here, which
makes hallucination detectable.

Schema per line (Local Intelligence Layer v2, Section 3.3):
{
  "ts": ISO-8601 UTC,
  "source": "ucb1_bandit | pool_flight | thermal | profitability | admission",
  "event": str,
  "detail": {...},
  "state_before": {...},
  "state_after": {...},
  "reason_code": str
}

Author: XMRig Automation
License: MIT
"""

import json
import os
import threading
from datetime import datetime, timezone
from typing import Optional

DEFAULT_LOG_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "logs", "decision_log.jsonl"
)

_lock = threading.Lock()


class DecisionLogger:
    """Thread-safe append-only JSONL decision logger."""

    def __init__(self, log_path: str = DEFAULT_LOG_PATH):
        self.log_path = log_path
        os.makedirs(os.path.dirname(log_path), exist_ok=True)

    def log(
        self,
        source: str,
        event: str,
        reason_code: str,
        detail: Optional[dict] = None,
        state_before: Optional[dict] = None,
        state_after: Optional[dict] = None,
    ) -> dict:
        """Append one decision record. Returns the record written."""
        record = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "source": source,
            "event": event,
            "detail": detail or {},
            "state_before": state_before or {},
            "state_after": state_after or {},
            "reason_code": reason_code,
        }
        line = json.dumps(record, separators=(",", ":"))
        with _lock:
            with open(self.log_path, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        return record

    def tail(self, n: int = 50) -> list:
        """Return the last n records (for advisor context building)."""
        if not os.path.exists(self.log_path):
            return []
        with open(self.log_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        records = []
        for line in lines[-n:]:
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        return records
