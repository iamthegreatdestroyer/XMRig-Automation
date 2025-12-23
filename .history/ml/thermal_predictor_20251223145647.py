"""
Thermal Prediction Module for XMRig Mining
Predictive thermal management to prevent CPU throttling using linear regression.
"""
from collections import deque
from dataclasses import dataclass
from typing import Tuple, Optional, Callable
import time
import statistics


@dataclass
class ThermalConfig:
    """Configuration for thermal management."""
    max_temp: float = 85.0          # Emergency throttle threshold (°C)
    target_temp: float = 75.0       # Optimal operating temperature (°C)
    prediction_horizon: int = 10    # Seconds to predict ahead
    window_size: int = 30           # Sliding window sample count
    throttle_margin: float = 5.0    # Preemptive throttle margin (°C)
    recovery_margin: float = 10.0   # Temp below target to recover


class ThermalPredictor:
    """Predicts CPU temperature using linear regression on sliding window."""
    
    def __init__(self, config: Optional[ThermalConfig] = None):
        self.config = config or ThermalConfig()
        self._readings: deque = deque(maxlen=self.config.window_size)
        self._timestamps: deque = deque(maxlen=self.config.window_size)
    
    def add_reading(self, temp: float, timestamp: Optional[float] = None) -> None:
        """Add a temperature reading to the sliding window."""
        self._readings.append(temp)
        self._timestamps.append(timestamp or time.time())
    
    def _linear_regression(self) -> Tuple[float, float]:
        """Compute slope and intercept via least squares."""
        n = len(self._readings)
        if n < 2:
            return 0.0, self._readings[-1] if self._readings else 0.0
        
        t0 = self._timestamps[0]
        x = [t - t0 for t in self._timestamps]
        y = list(self._readings)
        x_mean, y_mean = statistics.mean(x), statistics.mean(y)
        
        num = sum((xi - x_mean) * (yi - y_mean) for xi, yi in zip(x, y))
        den = sum((xi - x_mean) ** 2 for xi in x)
        
        if den == 0:
            return 0.0, y_mean
        slope = num / den
        return slope, y_mean - slope * x_mean
    
    def predict(self, seconds_ahead: Optional[int] = None) -> float:
        """Predict temperature N seconds into the future."""
        if len(self._readings) < 2:
            return self._readings[-1] if self._readings else 0.0
        
        horizon = seconds_ahead or self.config.prediction_horizon
        slope, _ = self._linear_regression()
        predicted = self._readings[-1] + (slope * horizon)
        return max(0.0, min(predicted, 120.0))
    
    def get_trend(self) -> str:
        """Get temperature trend: 'rising', 'falling', or 'stable'."""
        if len(self._readings) < 3:
            return "stable"
        slope, _ = self._linear_regression()
        if slope > 0.1:
            return "rising"
        elif slope < -0.1:
            return "falling"
        return "stable"
    
    def should_throttle(self) -> Tuple[bool, float]:
        """Determine if preemptive throttling is needed."""
        if not self._readings:
            return False, 0.0
        
        current, predicted = self._readings[-1], self.predict()
        if current >= self.config.max_temp:
            return True, predicted
        if predicted >= self.config.max_temp - self.config.throttle_margin:
            return True, predicted
        return False, predicted
    
    @property
    def current_temp(self) -> float:
        return self._readings[-1] if self._readings else 0.0
    
    @property
    def sample_count(self) -> int:
        return len(self._readings)


class ThermalController:
    """Controls mining intensity based on thermal predictions."""
    
    def __init__(
        self,
        config: Optional[ThermalConfig] = None,
        thread_adjuster: Optional[Callable[[int], None]] = None,
        temp_reader: Optional[Callable[[], float]] = None,
        max_threads: int = 8,
        min_threads: int = 1
    ):
        self.config = config or ThermalConfig()
        self.predictor = ThermalPredictor(self.config)
        self._adjuster = thread_adjuster
        self._reader = temp_reader
        self.max_threads, self.min_threads = max_threads, min_threads
        self.current_threads = max_threads
        self._throttled = False
        self._last_adjust = 0.0
        self._cooldown = 5.0
    
    def update(self) -> dict:
        """Main control loop iteration. Call periodically."""
        if self._reader:
            self.predictor.add_reading(self._reader())
        
        throttle, pred = self.predictor.should_throttle()
        current = self.predictor.current_temp
        trend = self.predictor.get_trend()
        action = "none"
        now = time.time()
        
        if now - self._last_adjust >= self._cooldown:
            if throttle and not self._throttled:
                action = self._reduce()
                self._throttled = True
                self._last_adjust = now
            elif self._throttled and self._can_recover(current, pred, trend):
                action = self._increase()
                if self.current_threads >= self.max_threads:
                    self._throttled = False
                self._last_adjust = now
        
        return {"temp": current, "predicted": pred, "trend": trend,
                "threads": self.current_threads, "throttled": self._throttled, "action": action}
    
    def _can_recover(self, current: float, predicted: float, trend: str) -> bool:
        recovery_temp = self.config.target_temp - self.config.recovery_margin
        return current <= recovery_temp and predicted <= self.config.target_temp and trend != "rising"
    
    def _reduce(self) -> str:
        reduction = 2 if self.predictor.current_temp >= self.config.max_temp else 1
        new = max(self.min_threads, self.current_threads - reduction)
        if new != self.current_threads:
            self.current_threads = new
            if self._adjuster:
                self._adjuster(new)
            return f"reduced_to_{new}"
        return "at_minimum"
    
    def _increase(self) -> str:
        new = min(self.max_threads, self.current_threads + 1)
        if new != self.current_threads:
            self.current_threads = new
            if self._adjuster:
                self._adjuster(new)
            return f"increased_to_{new}"
        return "at_maximum"
    
    def inject_reading(self, temp: float, ts: Optional[float] = None) -> None:
        """Manually inject a temperature reading (for testing)."""
        self.predictor.add_reading(temp, ts)


# ============================================================================
# Usage Example
# ============================================================================
if __name__ == "__main__":
    print("=== Thermal Prediction Demo ===\n")
    
    # Create controller with mock functions
    temp_profile = [60, 63, 66, 69, 72, 75, 78, 80, 82, 80, 76, 72, 68, 64, 60]
    
    def adjuster(n): print(f"  [ADJUST] threads -> {n}")
    
    ctrl = ThermalController(
        config=ThermalConfig(max_temp=85, target_temp=75, prediction_horizon=5),
        thread_adjuster=adjuster, max_threads=8, min_threads=2
    )
    ctrl._cooldown = 0
    
    # Seed initial readings
    t0 = time.time()
    for i in range(5):
        ctrl.inject_reading(58 + i * 0.5, t0 + i)
    
    # Run simulation
    for i, temp in enumerate(temp_profile):
        ctrl.inject_reading(temp, t0 + 5 + i)
        throttle, pred = ctrl.predictor.should_throttle()
        trend = ctrl.predictor.get_trend()
        
        print(f"T+{i:02d}s: {temp:3.0f}°C | pred:{pred:5.1f}°C | {trend:7s} | "
              f"threads:{ctrl.current_threads} | throttle:{throttle}")
        
        if throttle and ctrl.current_threads > ctrl.min_threads:
            ctrl.current_threads -= 1
            adjuster(ctrl.current_threads)
        elif not throttle and ctrl._can_recover(temp, pred, trend):
            if ctrl.current_threads < ctrl.max_threads:
                ctrl.current_threads += 1
                adjuster(ctrl.current_threads)
