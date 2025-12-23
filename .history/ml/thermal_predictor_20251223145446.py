"""
Thermal Prediction Module for XMRig Mining
Implements predictive thermal management to prevent CPU throttling.

Uses linear regression on sliding window of temperature readings
to predict thermal trajectory and preemptively adjust mining intensity.
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
    sample_interval: float = 1.0    # Seconds between readings
    throttle_margin: float = 5.0    # Preemptive throttle margin (°C)
    recovery_margin: float = 10.0   # Temp below target to recover


class ThermalPredictor:
    """
    Predicts future CPU temperature using linear regression
    on a sliding window of temperature readings.
    """
    
    def __init__(self, config: Optional[ThermalConfig] = None):
        self.config = config or ThermalConfig()
        self._readings: deque = deque(maxlen=self.config.window_size)
        self._timestamps: deque = deque(maxlen=self.config.window_size)
    
    def add_reading(self, temp: float, timestamp: Optional[float] = None) -> None:
        """Add a temperature reading to the sliding window."""
        ts = timestamp if timestamp is not None else time.time()
        self._readings.append(temp)
        self._timestamps.append(ts)
    
    def _linear_regression(self) -> Tuple[float, float]:
        """
        Compute linear regression coefficients (slope, intercept).
        Uses least squares: y = mx + b
        """
        n = len(self._readings)
        if n < 2:
            return 0.0, self._readings[-1] if self._readings else 0.0
        
        # Normalize timestamps to start from 0
        t0 = self._timestamps[0]
        x = [t - t0 for t in self._timestamps]
        y = list(self._readings)
        
        x_mean = statistics.mean(x)
        y_mean = statistics.mean(y)
        
        # Calculate slope (m) and intercept (b)
        numerator = sum((xi - x_mean) * (yi - y_mean) for xi, yi in zip(x, y))
        denominator = sum((xi - x_mean) ** 2 for xi in x)
        
        if denominator == 0:
            return 0.0, y_mean
        
        slope = numerator / denominator
        intercept = y_mean - slope * x_mean
        
        return slope, intercept
    
    def predict(self, seconds_ahead: Optional[int] = None) -> float:
        """
        Predict temperature N seconds into the future.
        
        Args:
            seconds_ahead: Prediction horizon (defaults to config value)
            
        Returns:
            Predicted temperature in °C
        """
        if not self._readings:
            return 0.0
        
        if len(self._readings) < 2:
            return self._readings[-1]
        
        horizon = seconds_ahead if seconds_ahead is not None else self.config.prediction_horizon
        slope, intercept = self._linear_regression()
        
        # Normalize slope to per-second rate based on actual sample interval
        t0 = self._timestamps[0]
        time_span = self._timestamps[-1] - t0
        
        if time_span <= 0:
            return self._readings[-1]
        
        # Calculate temperature change per second
        temp_rate = slope  # Already in units/second from regression
        current_temp = self._readings[-1]
        
        # Predict future temp, but clamp to reasonable bounds
        predicted = current_temp + (temp_rate * horizon)
        return max(0.0, min(predicted, 120.0))  # Clamp 0-120°C
    
    def get_trend(self) -> str:
        """Get current temperature trend: 'rising', 'falling', or 'stable'."""
        if len(self._readings) < 3:
            return "stable"
        
        slope, _ = self._linear_regression()
        
        if slope > 0.1:
            return "rising"
        elif slope < -0.1:
            return "falling"
        return "stable"
    
    def should_throttle(self) -> Tuple[bool, float]:
        """
        Determine if preemptive throttling is needed.
        
        Returns:
            Tuple of (should_throttle: bool, predicted_temp: float)
        """
        if not self._readings:
            return False, 0.0
        
        current_temp = self._readings[-1]
        predicted_temp = self.predict()
        
        # Emergency: current temp exceeds max
        if current_temp >= self.config.max_temp:
            return True, predicted_temp
        
        # Preemptive: predicted temp will exceed threshold
        throttle_threshold = self.config.max_temp - self.config.throttle_margin
        if predicted_temp >= throttle_threshold:
            return True, predicted_temp
        
        return False, predicted_temp
    
    @property
    def current_temp(self) -> float:
        """Get most recent temperature reading."""
        return self._readings[-1] if self._readings else 0.0
    
    @property
    def sample_count(self) -> int:
        """Get current number of samples in window."""
        return len(self._readings)


class ThermalController:
    """
    Controls mining intensity based on thermal predictions.
    Integrates with optimizer to adjust thread count.
    """
    
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
        self._thread_adjuster = thread_adjuster
        self._temp_reader = temp_reader
        self.max_threads = max_threads
        self.min_threads = min_threads
        self.current_threads = max_threads
        self._throttled = False
        self._last_adjustment = 0.0
        self._cooldown_period = 5.0  # Min seconds between adjustments
    
    def update(self) -> dict:
        """
        Main control loop iteration. Call periodically.
        
        Returns:
            Status dict with current state and actions taken
        """
        # Read current temperature
        if self._temp_reader:
            temp = self._temp_reader()
            self.predictor.add_reading(temp)
        
        should_throttle, predicted_temp = self.predictor.should_throttle()
        current_temp = self.predictor.current_temp
        trend = self.predictor.get_trend()
        
        action = "none"
        now = time.time()
        
        # Respect cooldown between adjustments
        if now - self._last_adjustment < self._cooldown_period:
            return self._status(action, current_temp, predicted_temp, trend)
        
        if should_throttle and not self._throttled:
            # Reduce threads
            action = self._reduce_threads()
            self._throttled = True
            self._last_adjustment = now
            
        elif self._throttled and self._can_recover(current_temp, predicted_temp, trend):
            # Attempt recovery
            action = self._increase_threads()
            if self.current_threads >= self.max_threads:
                self._throttled = False
            self._last_adjustment = now
        
        return self._status(action, current_temp, predicted_temp, trend)
    
    def _can_recover(self, current: float, predicted: float, trend: str) -> bool:
        """Check if safe to increase thread count."""
        recovery_temp = self.config.target_temp - self.config.recovery_margin
        return (
            current <= recovery_temp and
            predicted <= self.config.target_temp and
            trend != "rising"
        )
    
    def _reduce_threads(self) -> str:
        """Reduce thread count by 1-2 based on severity."""
        reduction = 2 if self.predictor.current_temp >= self.config.max_temp else 1
        new_count = max(self.min_threads, self.current_threads - reduction)
        
        if new_count != self.current_threads:
            self.current_threads = new_count
            if self._thread_adjuster:
                self._thread_adjuster(new_count)
            return f"reduced_to_{new_count}"
        return "at_minimum"
    
    def _increase_threads(self) -> str:
        """Increase thread count by 1 during recovery."""
        new_count = min(self.max_threads, self.current_threads + 1)
        
        if new_count != self.current_threads:
            self.current_threads = new_count
            if self._thread_adjuster:
                self._thread_adjuster(new_count)
            return f"increased_to_{new_count}"
        return "at_maximum"
    
    def _status(self, action: str, current: float, predicted: float, trend: str) -> dict:
        """Build status dictionary."""
        return {
            "current_temp": current,
            "predicted_temp": predicted,
            "trend": trend,
            "threads": self.current_threads,
            "throttled": self._throttled,
            "action": action
        }
    
    def force_reading(self, temp: float) -> None:
        """Manually inject a temperature reading (for testing)."""
        self.predictor.add_reading(temp)


# ============================================================================
# Usage Examples
# ============================================================================

if __name__ == "__main__":
    import random
    
    # Example 1: Basic ThermalPredictor usage with simulated timestamps
    print("=== ThermalPredictor Demo ===")
    predictor = ThermalPredictor()
    
    # Simulate rising temperature with 1-second intervals
    base_temp = 60.0
    base_time = time.time()
    for i in range(20):
        temp = base_temp + i * 0.5 + random.uniform(-0.3, 0.3)
        predictor.add_reading(temp, timestamp=base_time + i)
    
    print(f"Samples: {predictor.sample_count}")
    print(f"Current temp: {predictor.current_temp:.1f}°C")
    print(f"Predicted in 10s: {predictor.predict():.1f}°C")
    print(f"Trend: {predictor.get_trend()}")
    throttle, pred = predictor.should_throttle()
    print(f"Should throttle: {throttle} (predicted: {pred:.1f}°C)")
    
    # Example 2: ThermalController with simulated readings
    print("\n=== ThermalController Demo ===")
    print("Simulating thermal cycle: ramp up -> throttle -> cool down -> recover\n")
    
    # Simulate thermal profile: ramp, plateau, cool
    temp_profile = [60, 63, 66, 69, 72, 75, 78, 80, 82, 79, 76, 72, 68, 64, 60]
    temp_idx = [0]
    
    def mock_temp_reader():
        idx = min(temp_idx[0], len(temp_profile) - 1)
        temp_idx[0] += 1
        return temp_profile[idx]
    
    def mock_thread_adjuster(count):
        print(f"  [ADJUST] Setting threads to {count}")
    
    controller = ThermalController(
        config=ThermalConfig(max_temp=85, target_temp=75, prediction_horizon=5),
        temp_reader=mock_temp_reader,
        thread_adjuster=mock_thread_adjuster,
        max_threads=8,
        min_threads=2
    )
    controller._cooldown_period = 0  # Disable for demo
    
    # Pre-populate with initial readings for stable predictions
    init_time = time.time()
    for i in range(5):
        controller.predictor.add_reading(58 + i, timestamp=init_time + i)
    
    for i in range(len(temp_profile)):
        # Inject reading with proper timestamp
        temp = temp_profile[i]
        controller.predictor.add_reading(temp, timestamp=init_time + 5 + i)
        
        should_throttle, pred = controller.predictor.should_throttle()
        trend = controller.predictor.get_trend()
        
        # Simulate controller decision
        status = controller._status("check", temp, pred, trend)
        
        print(f"T+{i:02d}s: {temp:4.0f}°C | pred:{pred:5.1f}°C | "
              f"{trend:7s} | threads:{controller.current_threads} | "
              f"throttle:{should_throttle}")
        
        # Manual control logic for demo clarity
        if should_throttle and controller.current_threads > controller.min_threads:
            controller.current_threads -= 1
            mock_thread_adjuster(controller.current_threads)
        elif not should_throttle and controller._can_recover(temp, pred, trend):
            if controller.current_threads < controller.max_threads:
                controller.current_threads += 1
                mock_thread_adjuster(controller.current_threads)
