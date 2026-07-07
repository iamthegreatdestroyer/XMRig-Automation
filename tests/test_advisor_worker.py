"""
Unit tests for dashboard/mining-dashboard.py's AdvisorWorker.

Verifies the QThread worker behind the "Ask the Miner" pane never lets
an exception escape (which would otherwise crash the whole dashboard —
see the fixed live bug where AdvisorWorker was referenced but undefined)
and always signals completion rather than blocking the caller.

Run: python -m pytest tests/test_advisor_worker.py -v
  or: python tests/test_advisor_worker.py
"""

import importlib.util
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from PyQt6.QtWidgets import QApplication  # noqa: E402

_app = QApplication.instance() or QApplication(sys.argv)

# dashboard/mining-dashboard.py has a hyphen -- not importable as a normal
# module name -- load it directly from its file path.
_DASHBOARD_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "dashboard", "mining-dashboard.py",
)
_spec = importlib.util.spec_from_file_location("mining_dashboard", _DASHBOARD_PATH)
mining_dashboard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mining_dashboard)

AdvisorWorker = mining_dashboard.AdvisorWorker


class TestAdvisorWorker(unittest.TestCase):

    def test_is_a_qthread_not_a_blocking_call(self):
        """The whole point of AdvisorWorker: ask_advisor() must be able to
        call .start() and return immediately, not block on inference."""
        from PyQt6.QtCore import QThread
        self.assertTrue(issubclass(AdvisorWorker, QThread))

    def test_emits_answer_text_on_success(self):
        worker = AdvisorWorker("Why did hashrate drop?")
        mock_resp = MagicMock(
            answer="Thermal throttling reduced threads.",
            fabricated_evidence=[], valid=True, confidence="high",
        )
        received = []
        worker.finished_signal.connect(lambda text: received.append(text))

        with patch("intelligence.advisor.MiningAdvisor") as MockAdvisor:
            MockAdvisor.return_value.answer.return_value = mock_resp
            worker.run()  # call directly -- testing run()'s logic, not real threading

        self.assertEqual(len(received), 1)
        self.assertIn("Thermal throttling reduced threads.", received[0])
        self.assertIn("high", received[0])

    def test_exception_never_escapes_run(self):
        """This is the exact failure mode of the original bug: an
        unhandled exception inside the worker must never propagate and
        crash the dashboard process. It must be caught and reported via
        the signal instead."""
        worker = AdvisorWorker("Any question")
        received = []
        worker.finished_signal.connect(lambda text: received.append(text))

        with patch("intelligence.advisor.MiningAdvisor",
                   side_effect=RuntimeError("ollama unreachable")):
            try:
                worker.run()
            except Exception as e:  # pragma: no cover - this must NOT happen
                self.fail(f"run() let an exception escape: {e}")

        self.assertEqual(len(received), 1)
        self.assertIn("ollama unreachable", received[0])

    def test_fabricated_evidence_surfaces_a_warning(self):
        worker = AdvisorWorker("Suspicious question")
        mock_resp = MagicMock(
            answer="Some answer", fabricated_evidence=[{"reason_code": "FAKE"}],
            valid=False, confidence="low",
        )
        received = []
        worker.finished_signal.connect(lambda text: received.append(text))

        with patch("intelligence.advisor.MiningAdvisor") as MockAdvisor:
            MockAdvisor.return_value.answer.return_value = mock_resp
            worker.run()

        self.assertIn("WARNING", received[0])
        self.assertIn("unverified evidence", received[0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
