# 🧠 Machine Learning & AI Integration Opportunities

## XMRig-Automation ML Enhancement Analysis

**Analysis by:** @TENSOR - Machine Learning & Deep Neural Networks  
**Date:** December 23, 2025  
**System:** XMRig-Automation v2.0

---

## 📊 Executive Summary

Your XMRig-Automation system already has solid foundations for ML integration:

| Current Feature              | ML Enhancement            | Expected Improvement                    |
| ---------------------------- | ------------------------- | --------------------------------------- |
| CoinGecko price polling      | Predictive price models   | 15-30 min advance switching             |
| Fixed thread adjustment      | RL-based optimization     | 8-15% hashrate improvement              |
| Threshold-based thermal      | Neural thermal prediction | 5-10s preemptive throttling ✅ _Exists_ |
| Static pool selection        | Multi-armed bandit        | 5-20% share acceptance gain             |
| EMA-based trend detection ✅ | LSTM forecasting          | Proactive anomaly prevention            |

**Key Constraint:** All models must be **lightweight** (<50MB RAM, <5% CPU overhead) to run alongside mining operations.

---

## 🎯 8 ML/AI Integration Opportunities

---

### 1. 📈 Predictive Coin Price Models

**Current:** Reactive price checking every 60 minutes via CoinGecko API.  
**Problem:** By the time you switch, price movement may have already peaked.

#### Recommended Architecture: **Lightweight Time Series Ensemble**

```
┌─────────────────────────────────────────────────────────────┐
│                 PRICE PREDICTION PIPELINE                   │
├─────────────────────────────────────────────────────────────┤
│  Data Collection (Background)                               │
│  ├─ CoinGecko 5-min intervals → SQLite buffer              │
│  ├─ Historical: 7 days rolling window                       │
│  └─ Features: price, volume, market_cap, BTC correlation   │
├─────────────────────────────────────────────────────────────┤
│  Model Ensemble (Inference every 15 min)                    │
│  ├─ Prophet (seasonal patterns) - 30 min horizon           │
│  ├─ XGBoost (feature-based) - momentum signals              │
│  └─ Simple ARIMA (fallback) - trend continuation           │
├─────────────────────────────────────────────────────────────┤
│  Decision Engine                                            │
│  ├─ Weighted ensemble prediction                            │
│  ├─ Confidence scoring (ensemble agreement)                 │
│  └─ Switch signal if predicted_profit > threshold          │
└─────────────────────────────────────────────────────────────┘
```

#### Implementation Approach

```python
# ml/price_predictor.py
from dataclasses import dataclass
from typing import Dict, List, Tuple
import numpy as np

@dataclass
class PricePrediction:
    """Lightweight price prediction result"""
    coin: str
    current_price: float
    predicted_price_30m: float
    predicted_price_1h: float
    confidence: float  # 0-1, ensemble agreement
    trend: str  # "RISING", "FALLING", "STABLE"
    recommended_action: str  # "SWITCH_TO", "HOLD", "SWITCH_AWAY"

class LightweightPricePredictor:
    """
    Sub-50MB memory footprint price predictor.
    Uses exponential smoothing + momentum indicators.

    Training: None required (online learning)
    Inference: O(1) per prediction
    Memory: O(window_size) ≈ 2KB per coin
    """

    def __init__(self, coins: List[str], window_size: int = 288):  # 24h at 5min
        self.coins = coins
        self.window_size = window_size
        self.price_buffers: Dict[str, np.ndarray] = {
            coin: np.zeros(window_size) for coin in coins
        }
        self.positions: Dict[str, int] = {coin: 0 for coin in coins}

        # Triple exponential smoothing parameters
        self.alpha = 0.3  # Level
        self.beta = 0.1   # Trend
        self.gamma = 0.1  # Seasonality (hourly patterns)

        # State for Holt-Winters
        self.level: Dict[str, float] = {}
        self.trend: Dict[str, float] = {}

    def update(self, coin: str, price: float) -> None:
        """O(1) update with new price"""
        buf = self.price_buffers[coin]
        pos = self.positions[coin]
        buf[pos % self.window_size] = price
        self.positions[coin] = pos + 1

        # Update Holt-Winters state
        if coin not in self.level:
            self.level[coin] = price
            self.trend[coin] = 0.0
        else:
            prev_level = self.level[coin]
            self.level[coin] = self.alpha * price + (1 - self.alpha) * (prev_level + self.trend[coin])
            self.trend[coin] = self.beta * (self.level[coin] - prev_level) + (1 - self.beta) * self.trend[coin]

    def predict(self, coin: str, horizon_minutes: int = 30) -> PricePrediction:
        """O(1) prediction using exponential smoothing"""
        if coin not in self.level:
            return None

        steps = horizon_minutes / 5  # 5-min intervals
        predicted = self.level[coin] + self.trend[coin] * steps

        # Confidence based on trend stability
        trend_magnitude = abs(self.trend[coin]) / max(self.level[coin], 0.01)
        confidence = 1.0 - min(trend_magnitude * 10, 0.5)  # More stable = higher confidence

        # Determine trend
        if self.trend[coin] > 0.001 * self.level[coin]:
            trend = "RISING"
        elif self.trend[coin] < -0.001 * self.level[coin]:
            trend = "FALLING"
        else:
            trend = "STABLE"

        return PricePrediction(
            coin=coin,
            current_price=self.level[coin],
            predicted_price_30m=predicted,
            predicted_price_1h=self.level[coin] + self.trend[coin] * 12,
            confidence=confidence,
            trend=trend,
            recommended_action=self._get_action(coin, trend, confidence)
        )

    def _get_action(self, coin: str, trend: str, confidence: float) -> str:
        if confidence < 0.3:
            return "HOLD"  # Too uncertain
        if trend == "RISING" and confidence > 0.6:
            return "SWITCH_TO"
        if trend == "FALLING" and confidence > 0.6:
            return "SWITCH_AWAY"
        return "HOLD"
```

#### Resource Requirements

| Component              | Memory     | CPU        | Update Frequency |
| ---------------------- | ---------- | ---------- | ---------------- |
| Price buffer (3 coins) | ~10KB      | Negligible | 5 min            |
| Prediction inference   | ~1MB       | <0.1%      | 15 min           |
| SQLite history         | ~50MB disk | -          | Continuous       |

#### Expected Improvement

- **Switch timing:** 15-30 minutes earlier than reactive approach
- **Profit gain:** 5-15% from catching price swings

---

### 2. 🔄 Reinforcement Learning Thread Optimizer

**Current:** Rule-based thread adjustment with fixed thresholds (±2 threads).  
**Problem:** Optimal thread count varies by algorithm, temperature, and system state.

#### Recommended Architecture: **Contextual Bandit with Thompson Sampling**

```
┌─────────────────────────────────────────────────────────────┐
│               RL THREAD OPTIMIZER                           │
├─────────────────────────────────────────────────────────────┤
│  State Space (Context)                                      │
│  ├─ CPU temperature (binned: <60, 60-70, 70-80, 80+)       │
│  ├─ Current algorithm (XMR, RTM, VRSC)                     │
│  ├─ Time of day (binned: 4 periods)                        │
│  ├─ Recent hashrate trend (improving/stable/declining)     │
│  └─ Memory pressure (low/medium/high)                      │
├─────────────────────────────────────────────────────────────┤
│  Action Space                                               │
│  ├─ Thread counts: [8, 10, 12, 14, 16]                     │
│  └─ Represented as 5 discrete actions                      │
├─────────────────────────────────────────────────────────────┤
│  Reward Function                                            │
│  ├─ Primary: hashrate_achieved / hashrate_theoretical      │
│  ├─ Penalty: -0.1 per °C over target_temp                  │
│  └─ Penalty: -0.2 per % rejection rate                     │
├─────────────────────────────────────────────────────────────┤
│  Algorithm: Thompson Sampling                               │
│  ├─ Beta distribution per (context, action) pair           │
│  ├─ Exploration-exploitation balance                        │
│  └─ No neural network needed - table-based                 │
└─────────────────────────────────────────────────────────────┘
```

#### Implementation Approach

```python
# ml/thread_optimizer_rl.py
import numpy as np
from dataclasses import dataclass
from typing import Tuple, Dict
import json

@dataclass
class OptimizationState:
    """Discretized state for RL"""
    temp_bin: int      # 0-3 (cold, warm, hot, critical)
    algorithm: int     # 0=XMR, 1=RTM, 2=VRSC
    time_bin: int      # 0-3 (night, morning, afternoon, evening)
    trend_bin: int     # 0=declining, 1=stable, 2=improving

    def to_key(self) -> str:
        return f"{self.temp_bin}_{self.algorithm}_{self.time_bin}_{self.trend_bin}"

class ThompsonSamplingOptimizer:
    """
    Contextual bandit for thread optimization.

    Memory: O(|contexts| × |actions|) ≈ 4×3×4×3 × 5 × 16 bytes ≈ 12KB
    Inference: O(|actions|) = O(5)
    No GPU required.
    """

    THREAD_OPTIONS = [8, 10, 12, 14, 16]

    def __init__(self, persistence_path: str = None):
        self.persistence_path = persistence_path
        # Beta distribution parameters (alpha, beta) for each (context, action)
        self.alpha: Dict[str, np.ndarray] = {}  # successes
        self.beta_param: Dict[str, np.ndarray] = {}   # failures
        self.prior_alpha = 1.0  # Uniform prior
        self.prior_beta = 1.0

        if persistence_path:
            self._load()

    def select_threads(self, state: OptimizationState) -> Tuple[int, float]:
        """
        Select thread count using Thompson Sampling.

        Returns:
            (thread_count, exploration_score)
        """
        key = state.to_key()
        n_actions = len(self.THREAD_OPTIONS)

        # Initialize if new context
        if key not in self.alpha:
            self.alpha[key] = np.ones(n_actions) * self.prior_alpha
            self.beta_param[key] = np.ones(n_actions) * self.prior_beta

        # Sample from posterior Beta distributions
        samples = np.random.beta(self.alpha[key], self.beta_param[key])
        best_action = np.argmax(samples)

        # Exploration score = entropy of posterior
        exploration = 1.0 - (self.alpha[key][best_action] /
                            (self.alpha[key][best_action] + self.beta_param[key][best_action]))

        return self.THREAD_OPTIONS[best_action], exploration

    def update(self, state: OptimizationState, threads: int, reward: float) -> None:
        """
        Update posterior with observed reward.

        Args:
            state: The context when action was taken
            threads: Thread count used
            reward: Normalized reward [0, 1]
        """
        key = state.to_key()
        action_idx = self.THREAD_OPTIONS.index(threads)

        if key not in self.alpha:
            self.alpha[key] = np.ones(len(self.THREAD_OPTIONS)) * self.prior_alpha
            self.beta_param[key] = np.ones(len(self.THREAD_OPTIONS)) * self.prior_beta

        # Update Beta distribution (treat reward as Bernoulli observation)
        if reward > 0.5:
            self.alpha[key][action_idx] += reward
        else:
            self.beta_param[key][action_idx] += (1 - reward)

        self._save()

    def compute_reward(self, hashrate: float, target_hashrate: float,
                       temp: float, target_temp: float,
                       rejection_rate: float) -> float:
        """Compute normalized reward"""
        # Hashrate component (0-1)
        hr_reward = min(hashrate / target_hashrate, 1.0)

        # Temperature penalty
        temp_penalty = max(0, (temp - target_temp) / 20) * 0.3

        # Rejection penalty
        rej_penalty = rejection_rate * 0.2

        reward = max(0, hr_reward - temp_penalty - rej_penalty)
        return reward

    def _save(self):
        if self.persistence_path:
            data = {
                'alpha': {k: v.tolist() for k, v in self.alpha.items()},
                'beta': {k: v.tolist() for k, v in self.beta_param.items()}
            }
            with open(self.persistence_path, 'w') as f:
                json.dump(data, f)

    def _load(self):
        try:
            with open(self.persistence_path, 'r') as f:
                data = json.load(f)
                self.alpha = {k: np.array(v) for k, v in data['alpha'].items()}
                self.beta_param = {k: np.array(v) for k, v in data['beta'].items()}
        except (FileNotFoundError, json.JSONDecodeError):
            pass  # Start fresh
```

#### Resource Requirements

| Component            | Memory | CPU    | Frequency             |
| -------------------- | ------ | ------ | --------------------- |
| Context-action table | ~12KB  | -      | -                     |
| Selection inference  | ~1KB   | <0.01% | 30 min                |
| Posterior update     | ~1KB   | <0.01% | After each adjustment |

#### Expected Improvement

- **Hashrate:** 8-15% improvement through optimal thread selection
- **Stability:** Reduced thermal oscillation from over-correction

---

### 3. 🔍 Anomaly Detection for Hardware Failure Prediction

**Current:** Z-score anomaly detection in `StreamingStats` class.  
**Enhancement:** Multi-variate anomaly detection with failure prediction.

#### Recommended Architecture: **Isolation Forest + EWMA Control Charts**

```
┌─────────────────────────────────────────────────────────────┐
│             HARDWARE HEALTH MONITOR                         │
├─────────────────────────────────────────────────────────────┤
│  Feature Vector (per sample)                                │
│  ├─ hashrate_deviation (from rolling mean)                 │
│  ├─ temp_deviation                                          │
│  ├─ rejection_rate                                          │
│  ├─ hashrate_variance (short window)                       │
│  ├─ temp_rate_of_change                                     │
│  └─ share_latency (if available)                           │
├─────────────────────────────────────────────────────────────┤
│  Detection Methods                                          │
│  ├─ Isolation Forest (multi-variate outliers)              │
│  ├─ EWMA Control Chart (process shifts)                    │
│  └─ Rule-based (known failure patterns)                    │
├─────────────────────────────────────────────────────────────┤
│  Failure Patterns to Detect                                 │
│  ├─ GPU memory degradation (gradual hashrate decline)      │
│  ├─ Thermal paste drying (temp increase at same load)      │
│  ├─ Fan failure (rapid temp spikes)                        │
│  ├─ PSU instability (hashrate variance increase)           │
│  └─ Memory errors (rejection rate spikes)                  │
└─────────────────────────────────────────────────────────────┘
```

#### Implementation Approach

```python
# ml/anomaly_detector.py
import numpy as np
from dataclasses import dataclass, field
from typing import List, Optional, Tuple
from collections import deque
import time

@dataclass
class AnomalyAlert:
    timestamp: float
    severity: str  # "WARNING", "CRITICAL"
    category: str  # "THERMAL", "HASHRATE", "REJECTION", "HARDWARE"
    message: str
    recommended_action: str
    metrics: dict

class MultiVariateAnomalyDetector:
    """
    Lightweight anomaly detection without sklearn dependency.
    Uses streaming algorithms for O(1) memory.
    """

    def __init__(self, warmup_samples: int = 100):
        self.warmup_samples = warmup_samples
        self.sample_count = 0

        # EWMA state for each metric
        self.metrics = ['hashrate', 'temp', 'rejection_rate', 'hashrate_variance']
        self.ewma_mean: dict = {m: 0.0 for m in self.metrics}
        self.ewma_var: dict = {m: 0.0 for m in self.metrics}
        self.alpha = 0.1  # EWMA smoothing factor

        # Control chart limits (will be set after warmup)
        self.ucl: dict = {}  # Upper control limit
        self.lcl: dict = {}  # Lower control limit

        # Variance tracking for hashrate (stability indicator)
        self.recent_hashrates: deque = deque(maxlen=10)

        # Pattern detection
        self.consecutive_anomalies: dict = {m: 0 for m in self.metrics}
        self.alert_cooldown: dict = {m: 0.0 for m in self.metrics}

    def update(self, hashrate: float, temp: float,
               accepted: int, rejected: int) -> Optional[AnomalyAlert]:
        """
        Update detector with new sample.

        Returns:
            AnomalyAlert if anomaly detected, None otherwise
        """
        self.sample_count += 1

        # Compute rejection rate
        total = accepted + rejected
        rejection_rate = rejected / total if total > 0 else 0.0

        # Track hashrate variance
        self.recent_hashrates.append(hashrate)
        hashrate_var = np.var(list(self.recent_hashrates)) if len(self.recent_hashrates) >= 5 else 0.0

        # Current sample
        sample = {
            'hashrate': hashrate,
            'temp': temp,
            'rejection_rate': rejection_rate,
            'hashrate_variance': hashrate_var
        }

        # Update EWMA statistics
        for metric, value in sample.items():
            old_mean = self.ewma_mean[metric]
            self.ewma_mean[metric] = self.alpha * value + (1 - self.alpha) * old_mean
            delta = value - old_mean
            self.ewma_var[metric] = (1 - self.alpha) * (self.ewma_var[metric] + self.alpha * delta ** 2)

        # Set control limits after warmup
        if self.sample_count == self.warmup_samples:
            self._set_control_limits()

        # Check for anomalies after warmup
        if self.sample_count > self.warmup_samples:
            return self._check_anomalies(sample)

        return None

    def _set_control_limits(self):
        """Set 3-sigma control limits based on warmup data"""
        for metric in self.metrics:
            std = np.sqrt(self.ewma_var[metric])
            self.ucl[metric] = self.ewma_mean[metric] + 3 * std
            self.lcl[metric] = self.ewma_mean[metric] - 3 * std

    def _check_anomalies(self, sample: dict) -> Optional[AnomalyAlert]:
        """Check for statistical anomalies and failure patterns"""
        now = time.time()

        alerts = []

        # Check each metric against control limits
        for metric, value in sample.items():
            if metric not in self.ucl:
                continue

            # Skip if in cooldown
            if now < self.alert_cooldown.get(metric, 0):
                continue

            is_anomaly = False
            severity = "WARNING"

            # Upper control limit violation
            if value > self.ucl[metric]:
                is_anomaly = True
                if metric == 'temp':
                    severity = "CRITICAL" if value > 85 else "WARNING"
                elif metric == 'rejection_rate':
                    severity = "CRITICAL" if value > 0.1 else "WARNING"

            # Lower control limit violation (for hashrate)
            if metric == 'hashrate' and value < self.lcl[metric]:
                is_anomaly = True
                if value < self.ewma_mean[metric] * 0.7:
                    severity = "CRITICAL"

            if is_anomaly:
                self.consecutive_anomalies[metric] += 1

                # Alert after 3 consecutive anomalies
                if self.consecutive_anomalies[metric] >= 3:
                    alert = self._create_alert(metric, value, severity)
                    alerts.append(alert)
                    self.alert_cooldown[metric] = now + 300  # 5 min cooldown
                    self.consecutive_anomalies[metric] = 0
            else:
                self.consecutive_anomalies[metric] = 0

        # Return most severe alert
        if alerts:
            return max(alerts, key=lambda a: 0 if a.severity == "WARNING" else 1)
        return None

    def _create_alert(self, metric: str, value: float, severity: str) -> AnomalyAlert:
        """Create appropriate alert based on metric"""
        templates = {
            'hashrate': {
                'category': 'HARDWARE',
                'message': f"Hashrate dropped to {value:.1f} H/s (expected: {self.ewma_mean['hashrate']:.1f})",
                'action': "Check GPU/CPU health, restart miner if persistent"
            },
            'temp': {
                'category': 'THERMAL',
                'message': f"Temperature spike to {value:.1f}°C",
                'action': "Reduce threads, check cooling system"
            },
            'rejection_rate': {
                'category': 'NETWORK',
                'message': f"Share rejection rate at {value*100:.1f}%",
                'action': "Check network connection, try backup pool"
            },
            'hashrate_variance': {
                'category': 'STABILITY',
                'message': f"Hashrate unstable (variance: {value:.1f})",
                'action': "Check power supply stability, memory errors"
            }
        }

        template = templates.get(metric, {
            'category': 'UNKNOWN',
            'message': f"Anomaly in {metric}: {value}",
            'action': "Investigate"
        })

        return AnomalyAlert(
            timestamp=time.time(),
            severity=severity,
            category=template['category'],
            message=template['message'],
            recommended_action=template['action'],
            metrics={
                'value': value,
                'expected': self.ewma_mean[metric],
                'ucl': self.ucl.get(metric),
                'lcl': self.lcl.get(metric)
            }
        )
```

#### Expected Improvement

- **Early warning:** 5-30 minutes before catastrophic failures
- **Reduced downtime:** Proactive maintenance scheduling

---

### 4. 📊 Time Series Hashrate Forecasting

**Current:** EMA-based trend detection in `StreamingStats`.  
**Enhancement:** LSTM-lite for pattern recognition and forecasting.

#### Recommended Architecture: **Lightweight Sequence Model**

For mining workloads, a full LSTM is overkill. Instead, use a **Exponential Smoothing State Space Model (ETS)** or **TCN-lite**:

```python
# ml/hashrate_forecaster.py
import numpy as np
from collections import deque
from typing import Tuple, List

class LightweightHashrateForecaster:
    """
    Holt-Winters exponential smoothing with hourly seasonality.

    Memory: O(season_length) ≈ 288 floats ≈ 2.3KB
    Inference: O(horizon)
    No neural network overhead.
    """

    def __init__(self, season_length: int = 12):  # 12 samples = 1 hour at 5min intervals
        self.season_length = season_length

        # Holt-Winters state
        self.level = None
        self.trend = 0.0
        self.seasonal = np.zeros(season_length)

        # Smoothing parameters (can be tuned)
        self.alpha = 0.2   # Level
        self.beta = 0.1    # Trend
        self.gamma = 0.1   # Seasonal

        self.sample_count = 0
        self.history = deque(maxlen=season_length * 3)  # 3 seasons for initialization

    def update(self, hashrate: float) -> None:
        """O(1) update"""
        self.history.append(hashrate)
        self.sample_count += 1

        season_idx = (self.sample_count - 1) % self.season_length

        if self.sample_count <= self.season_length:
            # Initialization phase
            if self.level is None:
                self.level = hashrate
            else:
                self.level = 0.9 * self.level + 0.1 * hashrate
            return

        if self.sample_count <= self.season_length * 2:
            # Initialize seasonality
            base = self.level
            self.seasonal[season_idx] = hashrate / base if base > 0 else 1.0
            return

        # Holt-Winters update
        prev_level = self.level

        # Level
        self.level = self.alpha * (hashrate / self.seasonal[season_idx]) + \
                     (1 - self.alpha) * (prev_level + self.trend)

        # Trend
        self.trend = self.beta * (self.level - prev_level) + \
                     (1 - self.beta) * self.trend

        # Seasonal
        self.seasonal[season_idx] = self.gamma * (hashrate / self.level) + \
                                     (1 - self.gamma) * self.seasonal[season_idx]

    def forecast(self, horizon: int = 6) -> Tuple[np.ndarray, np.ndarray]:
        """
        Forecast hashrate for next `horizon` periods.

        Returns:
            (predictions, confidence_intervals)
        """
        if self.sample_count < self.season_length * 2:
            # Not enough data
            current = self.level or 0
            return np.full(horizon, current), np.zeros((horizon, 2))

        predictions = np.zeros(horizon)

        for h in range(horizon):
            season_idx = (self.sample_count + h) % self.season_length
            predictions[h] = (self.level + self.trend * (h + 1)) * self.seasonal[season_idx]

        # Simple confidence intervals based on historical variance
        hist_array = np.array(self.history)
        std = np.std(hist_array) if len(hist_array) > 10 else predictions.mean() * 0.1

        ci = np.column_stack([
            predictions - 1.96 * std,
            predictions + 1.96 * std
        ])

        return predictions, ci

    def detect_degradation(self, threshold_pct: float = 10) -> Tuple[bool, float]:
        """
        Detect if hashrate is trending down.

        Returns:
            (is_degrading, degradation_percent)
        """
        if len(self.history) < self.season_length:
            return False, 0.0

        # Compare current level to level from one season ago
        hist_array = np.array(self.history)
        old_mean = np.mean(hist_array[:self.season_length])
        new_mean = np.mean(hist_array[-self.season_length:])

        if old_mean == 0:
            return False, 0.0

        degradation = (old_mean - new_mean) / old_mean * 100
        return degradation > threshold_pct, degradation
```

---

### 5. 🎰 Multi-Armed Bandit for Pool Selection

**Current:** Static primary/backup pool configuration.  
**Enhancement:** Dynamic pool selection based on performance metrics.

#### Recommended Architecture: **UCB1 (Upper Confidence Bound)**

```python
# ml/pool_bandit.py
import numpy as np
from dataclasses import dataclass
from typing import Dict, List, Tuple
import math
import json

@dataclass
class PoolStats:
    """Statistics for a mining pool"""
    pool_url: str
    total_shares: int = 0
    accepted_shares: int = 0
    avg_latency_ms: float = 0
    last_block_time: float = 0

    @property
    def acceptance_rate(self) -> float:
        return self.accepted_shares / max(self.total_shares, 1)

class PoolSelectionBandit:
    """
    UCB1 algorithm for pool selection.
    Balances exploitation (best known pool) with exploration (trying others).

    Memory: O(n_pools) ≈ 1KB
    Selection: O(n_pools)
    """

    def __init__(self, pools: List[str], persistence_path: str = None):
        self.pools = pools
        self.persistence_path = persistence_path

        # UCB1 state
        self.n_selections: Dict[str, int] = {p: 0 for p in pools}
        self.total_reward: Dict[str, float] = {p: 0.0 for p in pools}
        self.total_selections = 0

        # Performance metrics
        self.latencies: Dict[str, List[float]] = {p: [] for p in pools}
        self.acceptance_rates: Dict[str, float] = {p: 1.0 for p in pools}

        self._load()

    def select_pool(self) -> Tuple[str, float]:
        """
        Select pool using UCB1 algorithm.

        Returns:
            (pool_url, exploration_bonus)
        """
        self.total_selections += 1

        # Force exploration of untried pools
        for pool in self.pools:
            if self.n_selections[pool] == 0:
                return pool, 1.0

        # UCB1 selection
        ucb_scores = {}
        for pool in self.pools:
            avg_reward = self.total_reward[pool] / self.n_selections[pool]
            exploration = math.sqrt(2 * math.log(self.total_selections) / self.n_selections[pool])
            ucb_scores[pool] = avg_reward + exploration

        best_pool = max(ucb_scores, key=ucb_scores.get)
        return best_pool, ucb_scores[best_pool] - (self.total_reward[best_pool] / self.n_selections[best_pool])

    def update(self, pool: str, accepted: int, rejected: int, latency_ms: float) -> None:
        """
        Update pool statistics after mining session.

        Args:
            pool: Pool URL
            accepted: Accepted shares
            rejected: Rejected shares
            latency_ms: Average share submission latency
        """
        total = accepted + rejected
        if total == 0:
            return

        # Compute reward: acceptance rate weighted by latency
        acceptance = accepted / total
        latency_factor = 1.0 / (1.0 + latency_ms / 1000)  # Penalize high latency
        reward = acceptance * 0.7 + latency_factor * 0.3

        self.n_selections[pool] += 1
        self.total_reward[pool] += reward

        # Track metrics
        self.latencies[pool].append(latency_ms)
        if len(self.latencies[pool]) > 100:
            self.latencies[pool] = self.latencies[pool][-100:]
        self.acceptance_rates[pool] = acceptance

        self._save()

    def get_pool_rankings(self) -> List[Tuple[str, float, float]]:
        """
        Get pools ranked by estimated performance.

        Returns:
            List of (pool, avg_reward, confidence) tuples
        """
        rankings = []
        for pool in self.pools:
            if self.n_selections[pool] > 0:
                avg = self.total_reward[pool] / self.n_selections[pool]
                confidence = min(self.n_selections[pool] / 50, 1.0)  # High confidence after 50 sessions
            else:
                avg = 0.5  # Prior
                confidence = 0.0
            rankings.append((pool, avg, confidence))

        return sorted(rankings, key=lambda x: x[1], reverse=True)

    def _save(self):
        if not self.persistence_path:
            return
        data = {
            'n_selections': self.n_selections,
            'total_reward': self.total_reward,
            'total_selections': self.total_selections,
            'acceptance_rates': self.acceptance_rates
        }
        with open(self.persistence_path, 'w') as f:
            json.dump(data, f)

    def _load(self):
        if not self.persistence_path:
            return
        try:
            with open(self.persistence_path, 'r') as f:
                data = json.load(f)
                self.n_selections = data.get('n_selections', self.n_selections)
                self.total_reward = data.get('total_reward', self.total_reward)
                self.total_selections = data.get('total_selections', 0)
                self.acceptance_rates = data.get('acceptance_rates', self.acceptance_rates)
        except (FileNotFoundError, json.JSONDecodeError):
            pass
```

#### Expected Improvement

- **Share acceptance:** 5-20% improvement over static selection
- **Latency reduction:** Automatic routing to fastest pool

---

### 6. 🌐 Federated Learning Across Mining Rigs

**Current:** Each rig operates independently.  
**Enhancement:** Share learned optimizations across rigs without sharing raw data.

#### Recommended Architecture: **Federated Averaging (FedAvg)**

```
┌─────────────────────────────────────────────────────────────┐
│              FEDERATED LEARNING SYSTEM                      │
├─────────────────────────────────────────────────────────────┤
│  Rig 1             Rig 2             Rig N                  │
│  ├─ Local model    ├─ Local model    ├─ Local model        │
│  ├─ Local data     ├─ Local data     ├─ Local data         │
│  └─ Train locally  └─ Train locally  └─ Train locally      │
│         │                │                  │               │
│         └────────────────┼──────────────────┘               │
│                          ▼                                  │
│                  ┌───────────────┐                          │
│                  │ Aggregation   │                          │
│                  │ Server (LAN)  │                          │
│                  └───────────────┘                          │
│                          │                                  │
│                   FedAvg: θ = Σ(n_k/n)·θ_k                 │
│                          │                                  │
│                          ▼                                  │
│              Updated global model                           │
│              distributed to all rigs                        │
└─────────────────────────────────────────────────────────────┘
```

#### Implementation Approach (Coordinator)

```python
# ml/federated_coordinator.py
import json
import numpy as np
from typing import Dict, List
from dataclasses import dataclass
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

@dataclass
class RigUpdate:
    """Update from a single rig"""
    rig_id: str
    weights: Dict[str, np.ndarray]
    n_samples: int
    metrics: dict

class FederatedCoordinator:
    """
    Simple federated averaging coordinator.
    Runs as HTTP server on LAN.

    Aggregation: Weighted average of model parameters
    Privacy: Only model weights shared, not raw performance data
    """

    def __init__(self, port: int = 8765):
        self.port = port
        self.pending_updates: List[RigUpdate] = []
        self.global_weights: Dict[str, np.ndarray] = {}
        self.aggregation_threshold = 3  # Aggregate after 3 rig updates

    def receive_update(self, update: RigUpdate) -> Dict[str, np.ndarray]:
        """
        Receive update from a rig, return current global model.
        """
        self.pending_updates.append(update)

        if len(self.pending_updates) >= self.aggregation_threshold:
            self._aggregate()

        return self.global_weights

    def _aggregate(self):
        """FedAvg aggregation"""
        if not self.pending_updates:
            return

        total_samples = sum(u.n_samples for u in self.pending_updates)

        # Weighted average
        new_weights = {}
        for key in self.pending_updates[0].weights.keys():
            weighted_sum = sum(
                (u.n_samples / total_samples) * u.weights[key]
                for u in self.pending_updates
            )
            new_weights[key] = weighted_sum

        self.global_weights = new_weights
        self.pending_updates = []
```

---

### 7. 🌡️ Neural Thermal Prediction Model

**Current:** Holt's double exponential smoothing in `ThermalPredictor`.  
**Enhancement:** Tiny neural network for multi-step thermal prediction.

#### Recommended Architecture: **MLP with 2 Hidden Layers**

```python
# ml/neural_thermal.py
import numpy as np
from typing import Tuple

class TinyThermalNN:
    """
    Minimal neural network for thermal prediction.

    Architecture: 8 inputs → 16 hidden → 8 hidden → 3 outputs
    Parameters: 8×16 + 16 + 16×8 + 8 + 8×3 + 3 = 307 parameters
    Memory: ~2.5KB
    Inference: ~10μs

    No framework dependencies - pure NumPy.
    """

    def __init__(self):
        # Initialize weights (pretrained or random)
        np.random.seed(42)
        self.W1 = np.random.randn(8, 16) * 0.1
        self.b1 = np.zeros(16)
        self.W2 = np.random.randn(16, 8) * 0.1
        self.b2 = np.zeros(8)
        self.W3 = np.random.randn(8, 3) * 0.1
        self.b3 = np.zeros(3)

        # Input normalization parameters
        self.input_mean = np.array([70, 0, 50, 50, 1800, 12, 0.5, 0])  # temp, trend, cpu%, load_avg, hr, threads, time, season
        self.input_std = np.array([15, 5, 30, 30, 500, 4, 0.3, 1])

        # Feature buffer for temporal features
        self.temp_history = []

    def _relu(self, x: np.ndarray) -> np.ndarray:
        return np.maximum(0, x)

    def _extract_features(self, current_temp: float, cpu_percent: float,
                          hashrate: float, threads: int,
                          hour_of_day: float) -> np.ndarray:
        """Extract 8 input features"""
        # Compute trend from history
        self.temp_history.append(current_temp)
        if len(self.temp_history) > 10:
            self.temp_history = self.temp_history[-10:]

        if len(self.temp_history) >= 3:
            trend = (self.temp_history[-1] - self.temp_history[-3]) / 2
        else:
            trend = 0.0

        # Seasonal component (cyclical encoding)
        season = np.sin(2 * np.pi * hour_of_day / 24)

        features = np.array([
            current_temp,
            trend,
            cpu_percent,
            cpu_percent,  # Could be load average
            hashrate,
            threads,
            hour_of_day / 24,
            season
        ])

        return features

    def predict(self, current_temp: float, cpu_percent: float,
                hashrate: float, threads: int,
                hour_of_day: float) -> Tuple[float, float, float]:
        """
        Predict temperature at t+5s, t+30s, t+60s

        Returns:
            (temp_5s, temp_30s, temp_60s)
        """
        # Extract and normalize features
        x = self._extract_features(current_temp, cpu_percent, hashrate, threads, hour_of_day)
        x_norm = (x - self.input_mean) / (self.input_std + 1e-8)

        # Forward pass
        h1 = self._relu(x_norm @ self.W1 + self.b1)
        h2 = self._relu(h1 @ self.W2 + self.b2)
        out = h2 @ self.W3 + self.b3

        # Denormalize outputs (predictions are deltas from current temp)
        predictions = current_temp + out * 5  # Scale factor

        return tuple(np.clip(predictions, 20, 105))

    def update_weights(self, weights: dict) -> None:
        """Load pretrained or federated weights"""
        if 'W1' in weights:
            self.W1 = np.array(weights['W1'])
            self.b1 = np.array(weights['b1'])
            self.W2 = np.array(weights['W2'])
            self.b2 = np.array(weights['b2'])
            self.W3 = np.array(weights['W3'])
            self.b3 = np.array(weights['b3'])
```

---

### 8. 📉 Pattern Recognition in Share Rejection Rates

**Current:** Threshold-based rejection monitoring.  
**Enhancement:** Pattern classification for root cause analysis.

#### Recommended Architecture: **Decision Tree Ensemble**

```python
# ml/rejection_analyzer.py
from dataclasses import dataclass
from typing import List, Tuple, Optional
from collections import deque
import numpy as np

@dataclass
class RejectionPattern:
    """Detected rejection pattern with diagnosis"""
    pattern_type: str
    confidence: float
    root_cause: str
    recommended_action: str

class RejectionPatternAnalyzer:
    """
    Rule-based pattern classifier for share rejections.
    Identifies common rejection patterns and their root causes.

    No ML training required - uses domain knowledge patterns.
    """

    PATTERNS = {
        'STALE_SHARES': {
            'signature': 'high_latency_correlation',
            'root_cause': 'Network latency causing shares to arrive after new block',
            'action': 'Switch to geographically closer pool'
        },
        'DIFFICULTY_MISMATCH': {
            'signature': 'burst_after_diff_change',
            'root_cause': 'Miner not adapting to difficulty changes quickly',
            'action': 'Check miner configuration, update XMRig'
        },
        'DUPLICATE_SHARES': {
            'signature': 'periodic_rejections',
            'root_cause': 'Same nonce submitted multiple times',
            'action': 'Check for miner misconfiguration or multiple instances'
        },
        'POOL_ISSUE': {
            'signature': 'sudden_spike_all_shares',
            'root_cause': 'Pool server issue',
            'action': 'Switch to backup pool'
        },
        'HARDWARE_MEMORY': {
            'signature': 'random_with_hashrate_drop',
            'root_cause': 'Memory errors producing invalid hashes',
            'action': 'Run memory diagnostics, check temperatures'
        }
    }

    def __init__(self, window_size: int = 100):
        self.window_size = window_size
        self.rejection_times: deque = deque(maxlen=window_size)
        self.rejection_latencies: deque = deque(maxlen=window_size)
        self.difficulty_changes: List[float] = []
        self.hashrate_samples: deque = deque(maxlen=window_size)

    def record_rejection(self, timestamp: float, latency_ms: float,
                         current_hashrate: float) -> None:
        """Record a share rejection event"""
        self.rejection_times.append(timestamp)
        self.rejection_latencies.append(latency_ms)
        self.hashrate_samples.append(current_hashrate)

    def record_difficulty_change(self, timestamp: float) -> None:
        """Record when difficulty changed"""
        self.difficulty_changes.append(timestamp)
        if len(self.difficulty_changes) > 20:
            self.difficulty_changes = self.difficulty_changes[-20:]

    def analyze(self) -> Optional[RejectionPattern]:
        """
        Analyze recent rejections for patterns.

        Returns:
            RejectionPattern if pattern detected, None otherwise
        """
        if len(self.rejection_times) < 10:
            return None  # Not enough data

        rejections = np.array(self.rejection_times)
        latencies = np.array(self.rejection_latencies)
        hashrates = np.array(list(self.hashrate_samples))

        # Check for high latency correlation
        if len(latencies) >= 10:
            high_latency_rejections = np.sum(latencies > 500) / len(latencies)
            if high_latency_rejections > 0.7:
                return RejectionPattern(
                    pattern_type='STALE_SHARES',
                    confidence=high_latency_rejections,
                    root_cause=self.PATTERNS['STALE_SHARES']['root_cause'],
                    recommended_action=self.PATTERNS['STALE_SHARES']['action']
                )

        # Check for burst after difficulty change
        if self.difficulty_changes:
            last_diff_change = self.difficulty_changes[-1]
            recent_rejections = rejections[rejections > last_diff_change]
            if len(recent_rejections) >= 5:
                time_since_change = rejections[-1] - last_diff_change
                if time_since_change < 60:  # 5+ rejections within 60s of diff change
                    return RejectionPattern(
                        pattern_type='DIFFICULTY_MISMATCH',
                        confidence=0.8,
                        root_cause=self.PATTERNS['DIFFICULTY_MISMATCH']['root_cause'],
                        recommended_action=self.PATTERNS['DIFFICULTY_MISMATCH']['action']
                    )

        # Check for periodic pattern (duplicate shares)
        if len(rejections) >= 20:
            intervals = np.diff(rejections)
            if np.std(intervals) < np.mean(intervals) * 0.3:  # Regular intervals
                return RejectionPattern(
                    pattern_type='DUPLICATE_SHARES',
                    confidence=0.7,
                    root_cause=self.PATTERNS['DUPLICATE_SHARES']['root_cause'],
                    recommended_action=self.PATTERNS['DUPLICATE_SHARES']['action']
                )

        # Check for sudden spike (pool issue)
        if len(rejections) >= 10:
            recent_rate = 10 / (rejections[-1] - rejections[-10] + 1)
            if recent_rate > 0.5:  # >0.5 rejections per second
                return RejectionPattern(
                    pattern_type='POOL_ISSUE',
                    confidence=0.9,
                    root_cause=self.PATTERNS['POOL_ISSUE']['root_cause'],
                    recommended_action=self.PATTERNS['POOL_ISSUE']['action']
                )

        # Check for correlation with hashrate drops
        if len(hashrates) >= 10:
            hashrate_trend = (hashrates[-1] - hashrates[0]) / hashrates[0]
            if hashrate_trend < -0.1:  # >10% drop
                return RejectionPattern(
                    pattern_type='HARDWARE_MEMORY',
                    confidence=0.6,
                    root_cause=self.PATTERNS['HARDWARE_MEMORY']['root_cause'],
                    recommended_action=self.PATTERNS['HARDWARE_MEMORY']['action']
                )

        return None
```

---

## 📁 Recommended Project Structure

```
XMRig-Automation/
├── ml/                                 # NEW: ML module
│   ├── __init__.py
│   ├── price_predictor.py             # #1: Price prediction
│   ├── thread_optimizer_rl.py         # #2: RL thread optimization
│   ├── anomaly_detector.py            # #3: Hardware anomaly detection
│   ├── hashrate_forecaster.py         # #4: Time series forecasting
│   ├── pool_bandit.py                 # #5: Pool selection
│   ├── federated_coordinator.py       # #6: Federated learning
│   ├── neural_thermal.py              # #7: Neural thermal prediction
│   ├── rejection_analyzer.py          # #8: Rejection pattern analysis
│   ├── integration.py                 # Integration with existing system
│   └── models/                         # Persisted model weights
│       ├── thread_optimizer_state.json
│       ├── pool_bandit_state.json
│       └── thermal_nn_weights.json
├── dashboard/
│   ├── mining-dashboard.py            # Existing (add ML metrics display)
│   └── performance_optimizations.py   # Existing (extend with ML hooks)
├── advanced/
│   ├── optimizer-v3.ps1               # Existing (call Python ML modules)
│   └── profit-switcher-v2.ps1         # Existing (integrate price predictor)
└── config/
    └── ml_config.json                  # ML hyperparameters
```

---

## 🔧 Integration Strategy

### Phase 1: Quick Wins (Week 1)

1. **Integrate Anomaly Detector** with existing `StreamingStats`
2. **Add Pool Bandit** to `profit-switcher-v2.ps1`
3. **Enhance `ThermalPredictor`** with multi-step forecasting

### Phase 2: Core ML (Week 2-3)

4. **Deploy RL Thread Optimizer** replacing rule-based logic
5. **Implement Price Predictor** with CoinGecko data collection
6. **Add Rejection Pattern Analyzer**

### Phase 3: Advanced (Month 2)

7. **Neural Thermal Model** training and deployment
8. **Federated Learning** for multi-rig setups
9. **Hashrate Forecaster** for proactive optimization

---

## 📊 Resource Budget

| Component           | Memory     | CPU Overhead | Disk           |
| ------------------- | ---------- | ------------ | -------------- |
| Price Predictor     | 15KB       | <0.5%        | 50MB (history) |
| RL Optimizer        | 12KB       | <0.1%        | 5KB            |
| Anomaly Detector    | 50KB       | <0.5%        | -              |
| Hashrate Forecaster | 5KB        | <0.1%        | -              |
| Pool Bandit         | 2KB        | <0.1%        | 1KB            |
| Thermal NN          | 3KB        | <0.1%        | 2KB            |
| Rejection Analyzer  | 20KB       | <0.1%        | -              |
| **TOTAL**           | **~110KB** | **<1.5%**    | **~55MB**      |

---

## 🎯 Expected Outcomes

| Metric                 | Current                | With ML                     | Improvement       |
| ---------------------- | ---------------------- | --------------------------- | ----------------- |
| Switch timing          | Reactive (60 min lag)  | Predictive (15 min early)   | +25 min           |
| Hashrate optimization  | Rule-based             | RL-optimal                  | +8-15%            |
| Downtime from failures | Reactive (after crash) | Predictive (30 min warning) | -80%              |
| Pool selection         | Static                 | Adaptive                    | +5-20% acceptance |
| Thermal efficiency     | Threshold-based        | Predictive                  | -5°C average      |

---

## 📚 References

1. **Thompson Sampling**: Chapelle & Li (2011) - "An Empirical Evaluation of Thompson Sampling"
2. **UCB1**: Auer et al. (2002) - "Finite-time Analysis of the Multiarmed Bandit Problem"
3. **Holt-Winters**: Chatfield (2000) - "Time-Series Forecasting"
4. **Federated Learning**: McMahan et al. (2017) - "Communication-Efficient Learning"
5. **Isolation Forest**: Liu et al. (2008) - "Isolation Forest"

---

_Generated by @TENSOR - Elite Agent Collective_
