"""
Unit tests for intelligence/admission.py
Run: python -m pytest tests/test_admission.py -v
  or: python tests/test_admission.py
"""

import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from intelligence.admission import (  # noqa: E402
    AdmissionController, InferenceJob, Mode,
    FULL_THREADS, REDUCED_THREADS,
)
from intelligence.decision_logger import DecisionLogger  # noqa: E402


def make_controller(mining=True, hashrate=4000.0, gate=True):
    """Controller with fully mocked XMRig client and instant inference."""
    client = MagicMock()
    client.is_running.return_value = mining

    summary = MagicMock()
    summary.hashrate_10s = hashrate
    client.get_summary.return_value = summary

    client.get_config.return_value = {"cpu": {"rx": list(FULL_THREADS)}}
    client.put_config.return_value = True

    tmp_log = tempfile.NamedTemporaryFile(
        suffix=".jsonl", delete=False).name
    ctrl = AdmissionController(
        xmrig_client=client,
        thermal_gate=lambda: gate,
        logger=DecisionLogger(tmp_log),
    )
    ctrl._run_inference = MagicMock(return_value='{"status": "ok"}')
    return ctrl, client


class TestAdmissionStateMachine(unittest.TestCase):

    def test_query_cycle_mining_to_query_to_mining(self):
        ctrl, client = make_controller()
        decision = ctrl.request(InferenceJob(prompt="test"))

        self.assertTrue(decision.admitted)
        self.assertEqual(ctrl.mode, Mode.MINING)  # restored

        # Verify downshift then restore via config PUT
        put_calls = [c.args[0]["cpu"]["rx"]
                     for c in client.put_config.call_args_list]
        self.assertEqual(put_calls[0], REDUCED_THREADS)
        self.assertEqual(put_calls[1], FULL_THREADS)
        # QUERY mode must NOT pause (dataset stays resident)
        client.pause.assert_not_called()

    def test_reflect_job_uses_pause_resume(self):
        ctrl, client = make_controller()
        decision = ctrl.request(InferenceJob(prompt="reflect", heavy=True))

        self.assertTrue(decision.admitted)
        client.pause.assert_called_once()
        client.resume.assert_called_once()
        client.put_config.assert_not_called()

    def test_thermal_gate_queues_instead_of_dropping(self):
        ctrl, client = make_controller(gate=False)
        decision = ctrl.request(InferenceJob(prompt="hot"))

        self.assertFalse(decision.admitted)
        self.assertEqual(decision.mode, Mode.COOLDOWN)
        self.assertEqual(decision.reason_code, "TEMP_FORECAST")
        self.assertEqual(len(ctrl._queue), 1)  # queued, not dropped
        client.put_config.assert_not_called()
        ctrl._run_inference.assert_not_called()

    def test_queue_drains_when_gate_clears(self):
        gate_state = {"safe": False}
        ctrl, _ = make_controller()
        ctrl.thermal_gate = lambda: gate_state["safe"]

        ctrl.request(InferenceJob(prompt="queued"))
        self.assertEqual(len(ctrl._queue), 1)

        gate_state["safe"] = True
        ran = ctrl.drain_queue()
        self.assertEqual(ran, 1)
        self.assertEqual(len(ctrl._queue), 0)

    def test_miner_not_running_skips_xmrig_control(self):
        ctrl, client = make_controller(mining=False)
        decision = ctrl.request(InferenceJob(prompt="no miner"))

        self.assertTrue(decision.admitted)
        client.put_config.assert_not_called()
        client.pause.assert_not_called()

    def test_canary_flag_persists_on_no_recovery(self):
        ctrl, client = make_controller(hashrate=4000.0)
        # After restore, hashrate stays at 10% of baseline -> no recovery
        recovering = MagicMock()
        recovering.hashrate_10s = 400.0
        baseline = MagicMock()
        baseline.hashrate_10s = 4000.0
        client.get_summary.side_effect = [baseline] + [recovering] * 50

        import intelligence.admission as adm
        original = adm.RECOVERY_TIMEOUT_S
        adm.RECOVERY_TIMEOUT_S = 0.1  # fast test
        try:
            ctrl.request(InferenceJob(prompt="degraded"))
        finally:
            adm.RECOVERY_TIMEOUT_S = original

        self.assertTrue(ctrl.downgrade_active)

    def test_inference_error_still_restores_mining(self):
        ctrl, client = make_controller()
        ctrl._run_inference = MagicMock(side_effect=RuntimeError("ollama down"))

        decision = ctrl.request(InferenceJob(prompt="fail"))

        self.assertTrue(decision.admitted)
        self.assertIn("ollama down", decision.metrics["error"])
        # Restore must happen despite the failure
        put_calls = [c.args[0]["cpu"]["rx"]
                     for c in client.put_config.call_args_list]
        self.assertEqual(put_calls[-1], FULL_THREADS)

    def test_decisions_are_logged(self):
        ctrl, _ = make_controller()
        ctrl.request(InferenceJob(prompt="log me"))
        records = ctrl.logger.tail(20)
        events = [r["event"] for r in records]
        self.assertIn("threads_set", events)
        self.assertIn("mode_change", events)
        for r in records:
            self.assertIn("ts", r)
            self.assertIn("reason_code", r)
            self.assertEqual(r["source"], "admission")


if __name__ == "__main__":
    unittest.main(verbosity=2)
