"""
Bayesian Threshold Optimizer for XMRig Coin Switching
Uses Thompson Sampling to optimize profit improvement thresholds.
"""

import json
import random
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple


@dataclass
class SwitchOutcome:
    """Records outcome of a coin switch decision."""
    threshold: float
    coin_from: str
    coin_to: str
    profit_before: float
    profit_after: float
    timestamp: str

    @property
    def was_profitable(self) -> bool:
        return self.profit_after > self.profit_before

    @property
    def actual_improvement(self) -> float:
        if self.profit_before == 0:
            return 0.0
        return ((self.profit_after - self.profit_before) / self.profit_before) * 100


class BayesianThresholdOptimizer:
    """
    Thompson Sampling optimizer for coin switching thresholds.
    Groups thresholds into 5% buckets and learns optimal switching points.
    """

    BUCKET_SIZE = 5.0
    BUCKETS = [5.0, 10.0, 15.0, 20.0, 25.0, 30.0]
    DEFAULT_THRESHOLD = 15.0

    def __init__(self, persistence_path: Optional[Path] = None):
        self.persistence_path = persistence_path or Path("threshold_optimizer.json")
        # Beta(alpha, beta) priors - start with uniform Beta(1, 1)
        self.posteriors: Dict[float, Tuple[float, float]] = {
            bucket: (1.0, 1.0) for bucket in self.BUCKETS
        }
        self.outcomes: List[SwitchOutcome] = []
        self._load()

    def _bucket_for_threshold(self, threshold: float) -> float:
        """Map threshold to nearest 5% bucket."""
        for bucket in self.BUCKETS:
            if threshold <= bucket:
                return bucket
        return self.BUCKETS[-1]

    def record_switch(
        self,
        threshold: float,
        coin_from: str,
        coin_to: str,
        profit_before: float,
        profit_after: float,
    ) -> SwitchOutcome:
        """Record a switch outcome and update posteriors."""
        outcome = SwitchOutcome(
            threshold=threshold,
            coin_from=coin_from,
            coin_to=coin_to,
            profit_before=profit_before,
            profit_after=profit_after,
            timestamp=datetime.utcnow().isoformat(),
        )
        self.outcomes.append(outcome)
        self._update_posterior(outcome)
        self._save()
        return outcome

    def _update_posterior(self, outcome: SwitchOutcome) -> None:
        """Update Beta posterior based on switch outcome."""
        bucket = self._bucket_for_threshold(outcome.threshold)
        alpha, beta = self.posteriors[bucket]

        if outcome.was_profitable:
            # Success: increment alpha
            self.posteriors[bucket] = (alpha + 1, beta)
        else:
            # Failure: increment beta
            self.posteriors[bucket] = (alpha, beta + 1)

    def get_optimal_threshold(self) -> float:
        """
        Use Thompson Sampling to select the best threshold bucket.
        Samples from each posterior and returns bucket with highest sample.
        """
        if not self.outcomes:
            return self.DEFAULT_THRESHOLD

        samples = {}
        for bucket, (alpha, beta) in self.posteriors.items():
            # Sample from Beta distribution
            samples[bucket] = random.betavariate(alpha, beta)

        # Return bucket with highest sampled probability
        return max(samples, key=samples.get)

    def get_switch_probability(self, improvement_pct: float) -> float:
        """
        Get probability that switching at given improvement will be profitable.
        Returns mean of posterior Beta distribution for the bucket.
        """
        bucket = self._bucket_for_threshold(improvement_pct)
        alpha, beta = self.posteriors[bucket]
        # Mean of Beta(alpha, beta) = alpha / (alpha + beta)
        return alpha / (alpha + beta)

    def get_bucket_stats(self) -> Dict[float, Dict]:
        """Get statistics for all buckets."""
        stats = {}
        for bucket, (alpha, beta) in self.posteriors.items():
            total = alpha + beta - 2  # Subtract prior
            stats[bucket] = {
                "successes": alpha - 1,
                "failures": beta - 1,
                "total_trials": max(0, total),
                "success_rate": alpha / (alpha + beta),
                "confidence": 1 - (2 / (alpha + beta)),  # Higher with more data
            }
        return stats

    def should_switch(self, improvement_pct: float, min_probability: float = 0.5) -> bool:
        """Recommend whether to switch based on improvement percentage."""
        prob = self.get_switch_probability(improvement_pct)
        return prob >= min_probability and improvement_pct >= 5.0

    def _save(self) -> None:
        """Persist state to JSON file."""
        data = {
            "posteriors": {str(k): list(v) for k, v in self.posteriors.items()},
            "outcomes": [asdict(o) for o in self.outcomes[-500:]],  # Keep last 500
        }
        self.persistence_path.write_text(json.dumps(data, indent=2))

    def _load(self) -> None:
        """Load state from JSON file."""
        if not self.persistence_path.exists():
            return
        try:
            data = json.loads(self.persistence_path.read_text())
            self.posteriors = {
                float(k): tuple(v) for k, v in data.get("posteriors", {}).items()
            }
            # Ensure all buckets exist
            for bucket in self.BUCKETS:
                if bucket not in self.posteriors:
                    self.posteriors[bucket] = (1.0, 1.0)
            self.outcomes = [
                SwitchOutcome(**o) for o in data.get("outcomes", [])
            ]
        except (json.JSONDecodeError, KeyError, TypeError):
            pass  # Use defaults on corruption


# CLI interface for profit-switcher-v2.ps1 integration
if __name__ == "__main__":
    import sys

    optimizer = BayesianThresholdOptimizer(
        Path(__file__).parent / "threshold_optimizer.json"
    )

    if len(sys.argv) < 2:
        print(f"THRESHOLD:{optimizer.get_optimal_threshold():.1f}")
        sys.exit(0)

    cmd = sys.argv[1].lower()

    if cmd == "threshold":
        print(f"{optimizer.get_optimal_threshold():.1f}")

    elif cmd == "probability" and len(sys.argv) >= 3:
        pct = float(sys.argv[2])
        print(f"{optimizer.get_switch_probability(pct):.3f}")

    elif cmd == "should_switch" and len(sys.argv) >= 3:
        pct = float(sys.argv[2])
        print("YES" if optimizer.should_switch(pct) else "NO")

    elif cmd == "record" and len(sys.argv) >= 7:
        # record <threshold> <coin_from> <coin_to> <profit_before> <profit_after>
        outcome = optimizer.record_switch(
            threshold=float(sys.argv[2]),
            coin_from=sys.argv[3],
            coin_to=sys.argv[4],
            profit_before=float(sys.argv[5]),
            profit_after=float(sys.argv[6]),
        )
        print(f"RECORDED:{'SUCCESS' if outcome.was_profitable else 'FAILURE'}")

    elif cmd == "stats":
        for bucket, stats in optimizer.get_bucket_stats().items():
            print(f"{bucket:.0f}%: {stats['success_rate']:.1%} ({stats['total_trials']:.0f} trials)")

    else:
        print("Usage: python bayesian_threshold_optimizer.py [threshold|probability <pct>|should_switch <pct>|record <args>|stats]")
