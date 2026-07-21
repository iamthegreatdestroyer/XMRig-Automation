"""
Unit tests for intelligence/ucb1_bandit.py (power-aware reward wiring)
Run: python -m pytest tests/test_ucb1_bandit.py -v
  or: python tests/test_ucb1_bandit.py
"""

import json
import math
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from intelligence.ucb1_bandit import (  # noqa: E402
    ARMS, ArmState, BanditState, _cores_for_hint, _normalize_reward,
    _read_current_hint, auto_record,
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


class TestRewardNormalization(unittest.TestCase):
    """UCB1 reward normalization: the exploration term assumes rewards in
    [0,1], but rewards are net USD/day (~+/-0.06). Without normalizing, the
    exploration bonus dwarfs the signal ~30x and the bandit never exploits."""

    def test_normalize_bounds_midpoint_and_clamp(self):
        self.assertAlmostEqual(_normalize_reward(-0.10), 0.0)
        self.assertAlmostEqual(_normalize_reward(0.10), 1.0)
        self.assertAlmostEqual(_normalize_reward(0.0), 0.5)
        # Rewards outside the plausible range clamp; never escape [0,1].
        self.assertEqual(_normalize_reward(5.0), 1.0)
        self.assertEqual(_normalize_reward(-5.0), 0.0)

    def test_ucb1_uses_normalized_exploitation_not_raw(self):
        # An arm with an absurd raw mean of 5.0 USD/day must contribute a
        # normalized (clamped-to-1.0) exploitation term, NOT the raw 5.0.
        arm = ArmState(hint=50, pulls=1, total_reward=5.0)  # mean == 5.0
        expected = 1.0 + math.sqrt(2 * math.log(2) / 1)
        self.assertAlmostEqual(arm.ucb1(total_pulls=2), expected, places=6)
        # The old (buggy) score would have been 5.0 + bonus (~6.18).
        self.assertLess(arm.ucb1(total_pulls=2), 2.5)

    def test_higher_reward_arm_scores_higher_at_equal_pulls(self):
        # At equal pull counts the exploration bonus cancels, so the better
        # net-USD/day arm must win -- and by the normalized gap, not the tiny
        # raw gap.
        good = ArmState(hint=50, pulls=20, total_reward=20 * 0.06)   # mean +0.06
        bad = ArmState(hint=100, pulls=20, total_reward=20 * -0.06)  # mean -0.06
        self.assertGreater(good.ucb1(total_pulls=40), bad.ucb1(total_pulls=40))

    def test_best_arm_still_ranks_by_raw_usd_per_day(self):
        # best_arm() (exploitation) must still pick highest raw USD/day, not
        # the normalized value. Set arm state directly to avoid record()'s
        # decision-log side effect.
        state = BanditState()
        for arm in state.arms:
            if arm.hint == 50:
                arm.pulls, arm.total_reward = 1, 0.06
            elif arm.hint == 62:
                arm.pulls, arm.total_reward = 1, 0.02
        self.assertEqual(state.best_arm().hint, 50)


if __name__ == "__main__":
    unittest.main(verbosity=2)
