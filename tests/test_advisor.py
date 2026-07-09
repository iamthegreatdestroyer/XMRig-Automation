"""
Unit tests for intelligence/advisor.py
Run: python -m pytest tests/test_advisor.py -v
  or: python tests/test_advisor.py
"""

import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from intelligence.advisor import (  # noqa: E402
    MiningAdvisor, _strip_thinking,
)
from intelligence.admission import AdmissionDecision, Mode  # noqa: E402
from intelligence.decision_logger import DecisionLogger  # noqa: E402


def make_advisor(logged_records=None):
    """Advisor with a fully mocked AdmissionController and a real
    DecisionLogger backed by a tempfile pre-seeded with `logged_records`."""
    tmp_log = tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False).name
    logger = DecisionLogger(tmp_log)
    for rec in (logged_records or []):
        logger.log(**rec)

    admission = MagicMock()
    telemetry_client = MagicMock()
    telemetry_client.get_summary.return_value = MagicMock(
        hashrate_10s=1500.0, hashrate_60s=1490.0, hashrate_15m=1480.0,
        threads=8, pool_url="pool.hashvault.pro:443",
        shares_accepted=10, shares_rejected=0, uptime=3600,
    )
    admission.client = telemetry_client

    return MiningAdvisor(admission=admission, logger=logger), admission


class TestStripThinking(unittest.TestCase):

    def test_removes_think_block(self):
        raw = "<think>reasoning about the problem...</think>## Summary\nDone."
        self.assertEqual(_strip_thinking(raw), "## Summary\nDone.")

    def test_removes_think_block_multiline(self):
        raw = "<think>\nline one\nline two\n</think>\n\n## Summary\nDone."
        self.assertEqual(_strip_thinking(raw), "## Summary\nDone.")

    def test_removes_outer_markdown_fence(self):
        raw = "```markdown\n## Summary\nDone.\n```"
        self.assertEqual(_strip_thinking(raw), "## Summary\nDone.")

    def test_removes_both_think_and_fence(self):
        raw = "<think>reasoning</think>```markdown\n## Summary\nDone.\n```"
        self.assertEqual(_strip_thinking(raw), "## Summary\nDone.")

    def test_passthrough_when_no_think_or_fence(self):
        raw = "## Summary\nAlready clean."
        self.assertEqual(_strip_thinking(raw), raw)


class TestAdvisorValidation(unittest.TestCase):

    def test_valid_json_with_real_evidence_passes(self):
        advisor, _ = make_advisor(logged_records=[
            dict(source="thermal", event="throttle_verdict_changed",
                 reason_code="TEMP_FORECAST", detail={}),
        ])
        raw = (
            '{"answer": "Throttled due to forecasted heat.", '
            '"evidence": [{"ts": "x", "reason_code": "TEMP_FORECAST", '
            '"event": "throttle_verdict_changed"}], '
            '"confidence": "high", "proposed_action": null}'
        )
        resp = advisor._validate(raw)
        self.assertTrue(resp.valid)
        self.assertEqual(resp.fabricated_evidence, [])

    def test_fabricated_reason_code_detected(self):
        advisor, _ = make_advisor(logged_records=[
            dict(source="thermal", event="throttle_verdict_changed",
                 reason_code="TEMP_FORECAST", detail={}),
        ])
        raw = (
            '{"answer": "Switched pools for a better rate.", '
            '"evidence": [{"ts": "x", "reason_code": "MADE_UP_CODE", '
            '"event": "pool_switched"}], '
            '"confidence": "high", "proposed_action": null}'
        )
        resp = advisor._validate(raw)
        self.assertFalse(resp.valid)
        self.assertEqual(len(resp.fabricated_evidence), 1)

    def test_malformed_json_is_invalid_not_a_crash(self):
        advisor, _ = make_advisor()
        resp = advisor._validate("not json at all")
        self.assertFalse(resp.valid)

    def test_proposed_action_always_forces_ratification(self):
        advisor, _ = make_advisor()
        raw = (
            '{"answer": "x", "evidence": [], "confidence": "low", '
            '"proposed_action": {"type": "pool_switch", "params": {}, '
            '"requires_ratification": false}}'
        )
        resp = advisor._validate(raw)
        self.assertTrue(resp.proposed_action["requires_ratification"])


class TestNightlyReflect(unittest.TestCase):

    def test_writes_file_when_admitted(self):
        advisor, admission = make_advisor(logged_records=[
            dict(source="admission", event="mode_change",
                 reason_code="DUTY_CYCLE", detail={}),
        ])
        admission.request.return_value = AdmissionDecision(
            admitted=True, mode=Mode.MINING, reason_code="ADMITTED_DUTY_CYCLE",
            result="## Summary\nAll normal.",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            import intelligence.advisor as adv
            original_dir = adv.REFLECTIONS_DIR
            adv.REFLECTIONS_DIR = tmpdir
            try:
                path = advisor.nightly_reflect()
            finally:
                adv.REFLECTIONS_DIR = original_dir
            self.assertIsNotNone(path)
            self.assertTrue(os.path.exists(path))
            with open(path, encoding="utf-8") as f:
                content = f.read()
            self.assertIn("All normal.", content)
            self.assertNotIn("<think>", content)

    def test_returns_none_when_thermally_deferred(self):
        advisor, admission = make_advisor()
        admission.request.return_value = AdmissionDecision(
            admitted=False, mode=Mode.COOLDOWN, reason_code="TEMP_FORECAST",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            import intelligence.advisor as adv
            original_dir = adv.REFLECTIONS_DIR
            adv.REFLECTIONS_DIR = tmpdir
            try:
                path = advisor.nightly_reflect()
            finally:
                adv.REFLECTIONS_DIR = original_dir
            self.assertIsNone(path)
            self.assertEqual(os.listdir(tmpdir), [])  # nothing written

    def test_idempotent_skips_rerun_if_already_written(self):
        advisor, admission = make_advisor()
        with tempfile.TemporaryDirectory() as tmpdir:
            import intelligence.advisor as adv
            original_dir = adv.REFLECTIONS_DIR
            adv.REFLECTIONS_DIR = tmpdir
            try:
                from datetime import datetime, timezone
                today = datetime.now(timezone.utc).date().isoformat()
                existing = os.path.join(tmpdir, f"{today}.md")
                with open(existing, "w") as f:
                    f.write("# already done")
                path = advisor.nightly_reflect()
            finally:
                adv.REFLECTIONS_DIR = original_dir
            self.assertEqual(path, existing)
            admission.request.assert_not_called()  # no inference re-run

    def test_uses_rolling_24h_window_not_utc_calendar_date(self):
        """Regression test: nightly_reflect must use a rolling 24h window,
        not a UTC-calendar-date string match, so a locally-scheduled run
        (e.g. 03:00 US Eastern = ~07:00-08:00 UTC) doesn't silently exclude
        most of the prior day's real events just because they fall on a
        different UTC calendar date than "now"."""
        advisor, admission = make_advisor()
        now = datetime.now(timezone.utc)
        old_ts = (now - timedelta(hours=25)).isoformat(timespec="seconds")
        recent_ts = (now - timedelta(hours=1)).isoformat(timespec="seconds")
        with open(advisor.logger.log_path, "a", encoding="utf-8") as f:
            for ts, code in [(old_ts, "OLD_MARKER"), (recent_ts, "RECENT_MARKER")]:
                f.write(json.dumps({
                    "ts": ts, "source": "thermal", "event": "marker_event",
                    "detail": {}, "state_before": {}, "state_after": {},
                    "reason_code": code,
                }) + "\n")

        admission.request.return_value = AdmissionDecision(
            admitted=True, mode=Mode.MINING, reason_code="ADMITTED_DUTY_CYCLE",
            result="## Summary\nfine.",
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            import intelligence.advisor as adv
            original_dir = adv.REFLECTIONS_DIR
            adv.REFLECTIONS_DIR = tmpdir
            try:
                advisor.nightly_reflect()
            finally:
                adv.REFLECTIONS_DIR = original_dir

        sent_prompt = admission.request.call_args[0][0].prompt
        self.assertIn("RECENT_MARKER", sent_prompt)
        self.assertNotIn("OLD_MARKER", sent_prompt)


if __name__ == "__main__":
    unittest.main(verbosity=2)
