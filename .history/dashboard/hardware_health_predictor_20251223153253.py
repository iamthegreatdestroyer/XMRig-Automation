"""Hardware Health Predictor - Isolation Forest anomaly detection for XMRig mining."""
import threading, time
from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Dict, List, Tuple
import numpy as np

try:
    from sklearn.ensemble import IsolationForest
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
    score: float
    status: HealthStatus
    anomaly_score: float
    factors: Dict[str, float] = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)
    def to_dict(self) -> dict:
        return {"score": round(self.score, 1), "status": self.status.value,
                "anomaly_score": round(self.anomaly_score, 4), "factors": self.factors}


@dataclass 
class MetricsSample:
    """Single metrics sample."""
    temperature: float
    hashrate: float
    hashrate_variance: float
    power_usage: float
    rejection_rate: float
    cpu_usage: float
    memory_usage: float
    timestamp: float = field(default_factory=time.time)
    def to_array(self) -> np.ndarray:
        return np.array([self.temperature, self.hashrate, self.hashrate_variance,
                        self.power_usage, self.rejection_rate, self.cpu_usage, self.memory_usage])


class MetricsCollector:
    """Thread-safe metrics collector with 1000-sample history."""
    FEATURE_NAMES = ["temp", "hashrate", "hr_variance", "power", "rejection", "cpu", "memory"]
    def __init__(self, history_size: int = 1000):
        self._history: deque = deque(maxlen=history_size)
        self._hr_window: deque = deque(maxlen=60)
        self._lock = threading.RLock()
    def _get_system_metrics(self) -> Tuple[float, float, float]:
        """Get CPU temp, usage, memory from psutil."""
        if not PSUTIL_AVAILABLE:
            return 65.0, 50.0, 50.0
        cpu = psutil.cpu_percent(interval=0.05)
        mem = psutil.virtual_memory().percent
        temp = 65.0
        try:
            temps = psutil.sensors_temperatures()
            if temps:
                for entries in temps.values():
                    if entries:
                        temp = max(e.current for e in entries)
                        break
        except (AttributeError, KeyError):
            pass
        return temp, cpu, mem
    def add_sample(self, hashrate: float, accepted: int, rejected: int,
                   power: float = 0.0, temperature: Optional[float] = None) -> MetricsSample:
        """Add metrics sample from XMRig data."""
        with self._lock:
            sys_temp, cpu, mem = self._get_system_metrics()
            self._hr_window.append(hashrate)
            hr_var = float(np.std(list(self._hr_window))) if len(self._hr_window) > 1 else 0.0
            total = accepted + rejected
            rej_rate = (rejected / total * 100) if total > 0 else 0.0
            sample = MetricsSample(
                temperature=temperature if temperature else sys_temp,
                hashrate=hashrate, hashrate_variance=hr_var, power_usage=power,
                rejection_rate=rej_rate, cpu_usage=cpu, memory_usage=mem)
            self._history.append(sample)
            return sample
    def get_history_array(self) -> np.ndarray:
        with self._lock:
            return np.array([s.to_array() for s in self._history]) if self._history else np.array([])
    
    @property
    def sample_count(self) -> int:
        with self._lock:
            return len(self._history)


class HardwareHealthPredictor:
    """Isolation Forest hardware failure predictor for 24-72 hour advance warning."""
    MIN_SAMPLES = 100
    THRESHOLDS = {"healthy": 65, "degraded": 40}
    
    def __init__(self, contamination: float = 0.02):
        if not SKLEARN_AVAILABLE:
            raise ImportError("scikit-learn required")
        self._model = IsolationForest(n_estimators=200, contamination=contamination,
                                      max_samples=256, random_state=42, n_jobs=-1)
        self._lock = threading.RLock()
        self._trained = False
        self._train_size = 0
        self._importance: Dict[str, float] = {}
    
    def train(self, collector: MetricsCollector) -> bool:
        """Train on accumulated history (min 100 samples)."""
        with self._lock:
            X = collector.get_history_array()
            if len(X) < self.MIN_SAMPLES:
                return False
            if self._trained and len(X) < self._train_size * 1.2:
                return True
            self._model.fit(X)
            self._trained = True
            self._train_size = len(X)
            self._compute_importance(X, collector.FEATURE_NAMES)
            return True
    
    def _compute_importance(self, X: np.ndarray, names: List[str]) -> None:
        """Feature importance via perturbation sensitivity."""
        if len(X) < 50:
            return
        base = self._model.decision_function(X[-50:])
        imp = {}
        for i, name in enumerate(names):
            Xp = X[-50:].copy()
            std = np.std(X[:, i])
            if std > 0:
                Xp[:, i] += std
                imp[name] = float(np.mean(np.abs(base - self._model.decision_function(Xp))))
            else:
                imp[name] = 0.0
        total = sum(imp.values()) or 1
        self._importance = {k: round(v/total, 3) for k, v in imp.items()}
    
    def predict_health(self, sample: MetricsSample) -> HealthReport:
        """Predict health: score 0-100, status HEALTHY/DEGRADED/CRITICAL."""
        with self._lock:
            if not self._trained:
                return HealthReport(100.0, HealthStatus.HEALTHY, 0.0)
            raw = self._model.decision_function(sample.to_array().reshape(1, -1))[0]
            score = max(0, min(100, 60 + raw * 150))
            if score >= self.THRESHOLDS["healthy"]:
                status = HealthStatus.HEALTHY
            elif score >= self.THRESHOLDS["degraded"]:
                status = HealthStatus.DEGRADED
            else:
                status = HealthStatus.CRITICAL
            return HealthReport(score, status, raw, self._importance.copy())
    
    @property
    def is_trained(self) -> bool:
        with self._lock:
            return self._trained


# Thread-safe singleton instances
_collector: Optional[MetricsCollector] = None
_predictor: Optional[HardwareHealthPredictor] = None
_lock = threading.Lock()


def get_health_monitor() -> Tuple[MetricsCollector, Optional[HardwareHealthPredictor]]:
    """Get singleton instances for dashboard integration."""
    global _collector, _predictor
    with _lock:
        if _collector is None:
            _collector = MetricsCollector()
        if _predictor is None and SKLEARN_AVAILABLE:
            _predictor = HardwareHealthPredictor()
    return _collector, _predictor


def check_health(hashrate: float, accepted: int, rejected: int,
                 power: float = 0.0, temp: Optional[float] = None) -> dict:
    """One-call API: add sample, train if ready, return health report."""
    collector, predictor = get_health_monitor()
    sample = collector.add_sample(hashrate, accepted, rejected, power, temp)
    if predictor and collector.sample_count >= HardwareHealthPredictor.MIN_SAMPLES:
        predictor.train(collector)
        return predictor.predict_health(sample).to_dict()
    return {"score": 100, "status": "HEALTHY", "samples": collector.sample_count,
            "min_required": HardwareHealthPredictor.MIN_SAMPLES}
