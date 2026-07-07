"""
Unit tests for ml/thermal_predictor.py decision-logging instrumentation.
Run: python -m pytest tests/test_thermal_predictor.py -v
  or: python tests/test_thermal_predictor.py
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ml.thermal_predictor import (  # noqa: E402
    ThermalConfig, ThermalController, ThermalPredictor,
)
from intelligence.decision_logger import DecisionLogger  # noqa: E402


class TestThrottleVerdictLogging(unittest.TestCase):

    def setUp(self):
        self.tmp_log = tempfile.NamedTemporaryFile(
            suffix=".jsonl", delete=False).name
        import ml.thermal_predictor as tp
        self._original_log = tp._log_decision
        self._logger = DecisionLogger(self.tmp_log)

        def patched_log(event, reason_code, detail, state_before=None,
                        state_after=None):
            self._logger.log(source="thermal", event=event,
                             reason_code=reason_code, detail=detail,
                             state_before=state_before, state_after=state_after)
        tp._log_decision = patched_log

    def tearDown(self):
        import ml.thermal_predictor as tp
        tp._log_decision = self._original_log

    def test_logs_only_on_verdict_change_not_every_call(self):
        predictor = ThermalPredictor(ThermalConfig(max_temp=85, throttle_margin=5))
        # Feed a flat, safe temperature 10 times -- verdict never changes
        # after the first call establishes it as False.
        for i in range(10):
            predictor.add_reading(60.0, timestamp=float(i))
            predictor.should_throttle()

        records = self._logger.tail(100)
        self.assertEqual(len(records), 1)  # only the initial None->False transition
        self.assertEqual(records[0]["reason_code"], "TEMP_NORMAL")

    def test_logs_transition_into_throttle(self):
        predictor = ThermalPredictor(ThermalConfig(max_temp=85, throttle_margin=5))
        predictor.add_reading(60.0, timestamp=0.0)
        predictor.should_throttle()  # None -> False (logged)

        # Force a hot reading well above max_temp
        predictor.add_reading(90.0, timestamp=1.0)
        predictor.should_throttle()  # False -> True (logged)

        records = self._logger.tail(100)
        self.assertEqual(len(records), 2)
        self.assertEqual(records[1]["state_after"]["should_throttle"], True)
        self.assertEqual(records[1]["reason_code"], "TEMP_AT_MAX")


class TestControllerActionLogging(unittest.TestCase):

    def setUp(self):
        self.tmp_log = tempfile.NamedTemporaryFile(
            suffix=".jsonl", delete=False).name
        import ml.thermal_predictor as tp
        self._original_log = tp._log_decision
        self._logger = DecisionLogger(self.tmp_log)

        def patched_log(event, reason_code, detail, state_before=None,
                        state_after=None):
            self._logger.log(source="thermal", event=event,
                             reason_code=reason_code, detail=detail,
                             state_before=state_before, state_after=state_after)
        tp._log_decision = patched_log

    def tearDown(self):
        import ml.thermal_predictor as tp
        tp._log_decision = self._original_log

    def test_reduce_logs_before_after_thread_counts(self):
        ctrl = ThermalController(max_threads=8, min_threads=2)
        ctrl.predictor.add_reading(90.0)  # hot enough to force -2 reduction
        ctrl._reduce()

        records = [r for r in self._logger.tail(100)
                   if r["event"] == "threads_reduced"]
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["state_before"]["threads"], 8)
        self.assertEqual(records[0]["state_after"]["threads"], 6)
        self.assertEqual(records[0]["reason_code"], "THERMAL_THROTTLE")

    def test_increase_logs_before_after_thread_counts(self):
        ctrl = ThermalController(max_threads=8, min_threads=2)
        ctrl.current_threads = 4
        ctrl._increase()

        records = [r for r in self._logger.tail(100)
                   if r["event"] == "threads_increased"]
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["state_before"]["threads"], 4)
        self.assertEqual(records[0]["state_after"]["threads"], 5)
        self.assertEqual(records[0]["reason_code"], "THERMAL_RECOVERY")

    def test_no_log_when_already_at_limit(self):
        ctrl = ThermalController(max_threads=8, min_threads=2)
        ctrl.current_threads = 8
        result = ctrl._increase()  # already at max, no-op

        self.assertEqual(result, "at_maximum")
        records = [r for r in self._logger.tail(100)
                   if r["event"] == "threads_increased"]
        self.assertEqual(len(records), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
