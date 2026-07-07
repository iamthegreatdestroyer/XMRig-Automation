"""
Unit tests for intelligence/ucb1_bandit.py (power-aware reward wiring)
Run: python -m pytest tests/test_ucb1_bandit.py -v
  or: python tests/test_ucb1_bandit.py
"""

import json
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from intelligence.ucb1_bandit import (  # noqa: E402
    ARMS, BanditState, _cores_for_hint, _read_current_hint, auto_record,
)


class TestCoresForHint(unittest.TestCase):

    def test_8_threads_is_physical_cores_only(self):
        self.assertEqual(_cores_for_hint(50), [0, 2, 4, 6, 8, 10, 12, 14])

    def test_16_threads_is_all_logical_cores(self):
        self.assertEqual(sorted(_cores_for_hint(100)), list(range(16)))

    def test_thread_count_matches_hint_percentage(self):
        for hint in ARMS:
            expected_threads = round(hint / 100 * 16)
            self.assertEqual(len(_cores_for_hint(hint)), expected_threads)

    def test_beyond_8_threads_adds_smt_siblings_not_new_physical(self):
        cores = _cores_for_hint(62)  # 10 threads
        physical = {0, 2, 4, 6, 8, 10, 12, 14}
        self.assertTrue(physical.issubset(set(cores)))
        self.assertEqual(len(cores), 10)


class TestReadCurrentHint(unittest.TestCase):

    def _write_config(self, cores):
        f = tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False)
        json.dump({"cpu": {"rx": cores}}, f)
        f.close()
        return f.name

    def test_recognizes_known_arm(self):
        path = self._write_config([0, 2, 4, 6, 8, 10, 12, 14])  # 8 threads
        self.assertEqual(_read_current_hint(path), 50)

    def test_returns_none_for_transient_non_arm_thread_count(self):
        # admission.py's REDUCED_THREADS mid-duty-cycle state (4 threads)
        # is not a bandit arm at all -- must not be misattributed
        path = self._write_config([0, 2, 4, 6])
        self.assertIsNone(_read_current_hint(path))

    def test_returns_none_for_missing_config(self):
        self.assertIsNone(_read_current_hint("/nonexistent/path.json"))


class TestAutoRecord(unittest.TestCase):

    def test_records_power_aware_reward_not_raw_hashrate(self):
        state = BanditState()
        cores = _cores_for_hint(50)  # 8 threads, a real arm

        with patch("intelligence.ucb1_bandit._read_current_hint",
                    return_value=50), \
             patch("dashboard.xmrig_api_client.get_client") as mock_get_client, \
             patch("intelligence.profitability.power_aware_reward",
                   return_value={"reward_usd_day": -0.0168, "profitable": False}):
            mock_client = MagicMock()
            mock_client.get_summary.return_value = MagicMock(hashrate_10s=1731.0)
            mock_get_client.return_value = mock_client

            reward = auto_record(state)

        self.assertEqual(reward, -0.0168)
        arm = next(a for a in state.arms if a.hint == 50)
        self.assertEqual(arm.pulls, 1)
        self.assertEqual(arm.total_reward, -0.0168)  # NOT 1731.0

    def test_skips_recording_when_hint_unattributable(self):
        state = BanditState()
        with patch("intelligence.ucb1_bandit._read_current_hint",
                    return_value=None):
            reward = auto_record(state)
        self.assertIsNone(reward)
        self.assertEqual(state.total_pulls, 0)

    def test_skips_recording_on_zero_hashrate(self):
        state = BanditState()
        with patch("intelligence.ucb1_bandit._read_current_hint",
                    return_value=50), \
             patch("dashboard.xmrig_api_client.get_client") as mock_get_client:
            mock_client = MagicMock()
            mock_client.get_summary.return_value = MagicMock(hashrate_10s=0.0)
            mock_get_client.return_value = mock_client
            reward = auto_record(state)
        self.assertIsNone(reward)
        self.assertEqual(state.total_pulls, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
