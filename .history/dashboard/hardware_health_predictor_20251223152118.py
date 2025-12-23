"""
Hardware Health Predictor for XMRig Mining
Isolation Forest-based anomaly detection for 24-72 hour advance failure warning.
"""
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Dict, List, Tuple
import numpy as np

try:
    from sklearn.ensemble import IsolationForest
    from sklearn.preprocessing import StandardScaler
    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False

try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False


class HealthStatus(Enum):
    HEALTHY = "HEALTHY"
    DEGRADED = "DEGRADED"
    CRITICAL = "CRITICAL"


@dataclass
class HealthReport:
    """Hardware health assessment result."""
    score: float  # 0-100, higher is healthier
    status: HealthStatus
    anomaly_score: float  # Raw isolation forest score
    contributing_factors: Dict[str, float] = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)
    
    def to_dict(self) -> dict:
        return {
            "score": round(self.score, 1),
            "status": self.status.value,
            "anomaly_score": round(self.anomaly_score, 4),
            "factors": self.contributing_factors,
            "timestamp": self.timestamp
        }


@dataclass
class MetricsSample:
    """Single metrics sample for analysis."""
    temperature: float
    hashrate: float
    hashrate_variance: float
    power_usage: float
    rejection_rate: float
    cpu_usage: float
    memory_usage: float
    timestamp: float = field(default_factory=time.time)
    
    def to_array(self) -> np.ndarray:
        return np.array([
            self.temperature, self.hashrate, self.hashrate_variance,
            self.power_usage, self.rejection_rate, self.cpu_usage, self.memory_usage
        ])


class MetricsCollector:
    """Thread-safe metrics collector with normalization."""
    
    FEATURE_NAMES = ["temp", "hashrate", "hr_variance", "power", "rejection", "cpu", "memory"]
    
    def __init__(self, history_size: int = 1000):
        self._history: deque = deque(maxlen=history_size)
        self._hashrate_window: deque = deque(maxlen=60)  # 1-min variance window
        self._lock = threading.RLock()
        self._scaler = StandardScaler() if SKLEARN_AVAILABLE else None
        self._scaler_fitted = False
    
    def collect_system_metrics(self) -> Tuple[float, float, float]:
        """Collect CPU temp, usage, and memory from system."""
        cpu_usage = memory_usage = temperature = 0.0
        if PSUTIL_AVAILABLE:
            cpu_usage = psutil.cpu_percent(interval=0.1)
            memory_usage = psutil.virtual_memory().percent
            try:
                temps = psutil.sensors_temperatures()
                if temps:
                    for name, entries in temps.items():
                        if entries:
                            temperature = max(e.current for e in entries)
                            break
            except (AttributeError, KeyError):
                temperature = 65.0  # Default fallback
        return temperature, cpu_usage, memory_usage
    
    def add_sample(self, hashrate: float, accepted: int, rejected: int,
                   power: float = 0.0, temperature: Optional[float] = None) -> MetricsSample:
        """Add metrics sample from XMRig and system data."""
        with self._lock:
            # Collect system metrics
            sys_temp, cpu_usage, memory_usage = self.collect_system_metrics()
            temp = temperature if temperature is not None else sys_temp
            
            # Calculate hashrate variance
            self._hashrate_window.append(hashrate)
            hr_variance = float(np.std(list(self._hashrate_window))) if len(self._hashrate_window) > 1 else 0.0
            
            # Calculate rejection rate
            total = accepted + rejected
            rejection_rate = (rejected / total * 100) if total > 0 else 0.0
            
            sample = MetricsSample(
                temperature=temp, hashrate=hashrate, hashrate_variance=hr_variance,
                power_usage=power, rejection_rate=rejection_rate,
                cpu_usage=cpu_usage, memory_usage=memory_usage
            )
            self._history.append(sample)
            return sample
    
    def get_history_array(self) -> np.ndarray:
        """Get normalized feature matrix from history."""
        with self._lock:
            if not self._history:
                return np.array([])
            raw = np.array([s.to_array() for s in self._history])
            if self._scaler and len(raw) >= 10:
                if not self._scaler_fitted:
                    self._scaler.fit(raw)
                    self._scaler_fitted = True
                return self._scaler.transform(raw)
            return raw
    
    def normalize_sample(self, sample: MetricsSample) -> np.ndarray:
        """Normalize single sample using fitted scaler."""
        with self._lock:
            raw = sample.to_array().reshape(1, -1)
            if self._scaler and self._scaler_fitted:
                return self._scaler.transform(raw)
            return raw
    
    @property
    def sample_count(self) -> int:
        with self._lock:
            return len(self._history)


class HardwareHealthPredictor:
    """Isolation Forest-based hardware failure predictor."""
    
    MIN_TRAINING_SAMPLES = 100
    SCORE_THRESHOLDS = {"healthy": 70, "degraded": 40}  # Below 40 = critical
    
    def __init__(self, contamination: float = 0.05):
        if not SKLEARN_AVAILABLE:
            raise ImportError("scikit-learn required: pip install scikit-learn")
        
        self._model = IsolationForest(
            n_estimators=100, contamination=contamination,
            random_state=42, n_jobs=-1, warm_start=True
        )
        self._lock = threading.RLock()
        self._trained = False
        self._last_training_size = 0
        self._feature_importance: Dict[str, float] = {}
    
    def train(self, collector: MetricsCollector) -> bool:
        """Train model on accumulated history."""
        with self._lock:
            X = collector.get_history_array()
            if len(X) < self.MIN_TRAINING_SAMPLES:
                return False
            
            # Retrain if significant new data (>20% more samples)
            if self._trained and len(X) < self._last_training_size * 1.2:
                return True
            
            self._model.fit(X)
            self._trained = True
            self._last_training_size = len(X)
            self._compute_feature_importance(X, collector.FEATURE_NAMES)
            return True
    
    def _compute_feature_importance(self, X: np.ndarray, names: List[str]) -> None:
        """Estimate feature importance via prediction sensitivity."""
        if not self._trained:
            return
        base_scores = self._model.decision_function(X[-50:])
        importance = {}
        for i, name in enumerate(names):
            X_perturbed = X[-50:].copy()
            X_perturbed[:, i] += np.std(X[:, i])
            perturbed_scores = self._model.decision_function(X_perturbed)
            importance[name] = float(np.mean(np.abs(base_scores - perturbed_scores)))
        total = sum(importance.values()) or 1
        self._feature_importance = {k: v / total for k, v in importance.items()}
    
    def predict_health(self, sample: MetricsSample, collector: MetricsCollector) -> HealthReport:
        """Predict hardware health from current metrics."""
        with self._lock:
            if not self._trained:
                return HealthReport(score=100.0, status=HealthStatus.HEALTHY, anomaly_score=0.0)
            
            X = collector.normalize_sample(sample)
            raw_score = self._model.decision_function(X)[0]
            
            # Convert to 0-100 scale (higher = healthier)
            # Isolation Forest: positive = normal, negative = anomaly
            health_score = max(0, min(100, 50 + raw_score * 50))
            
            # Determine status
            if health_score >= self.SCORE_THRESHOLDS["healthy"]:
                status = HealthStatus.HEALTHY
            elif health_score >= self.SCORE_THRESHOLDS["degraded"]:
                status = HealthStatus.DEGRADED
            else:
                status = HealthStatus.CRITICAL
            
            return HealthReport(
                score=health_score, status=status, anomaly_score=raw_score,
                contributing_factors=self._feature_importance.copy()
            )
    
    @property
    def is_trained(self) -> bool:
        with self._lock:
            return self._trained


# Singleton instances for dashboard integration
_collector: Optional[MetricsCollector] = None
_predictor: Optional[HardwareHealthPredictor] = None
_lock = threading.Lock()


def get_health_monitor() -> Tuple[MetricsCollector, HardwareHealthPredictor]:
    """Get or create singleton instances (thread-safe)."""
    global _collector, _predictor
    with _lock:
        if _collector is None:
            _collector = MetricsCollector()
        if _predictor is None and SKLEARN_AVAILABLE:
            _predictor = HardwareHealthPredictor()
    return _collector, _predictor


def check_health(hashrate: float, accepted: int, rejected: int,
                 power: float = 0.0, temp: Optional[float] = None) -> dict:
    """One-call API for dashboard integration."""
    collector, predictor = get_health_monitor()
    sample = collector.add_sample(hashrate, accepted, rejected, power, temp)
    
    if predictor and collector.sample_count >= HardwareHealthPredictor.MIN_TRAINING_SAMPLES:
        predictor.train(collector)
        report = predictor.predict_health(sample, collector)
        return report.to_dict()
    
    return {"score": 100, "status": "HEALTHY", "samples": collector.sample_count,
            "training_required": HardwareHealthPredictor.MIN_TRAINING_SAMPLES}
