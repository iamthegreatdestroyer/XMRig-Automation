"""
Thermal Prediction Module - Preemptive Throttling System
=========================================================
Predicts CPU temperature trajectory to prevent throttling
before it occurs.

Features:
- Linear regression on sliding window of temperatures
- Preemptive throttling 5-10 seconds before threshold
- Recovery detection with hysteresis
- Thread adjustment recommendations

Author: XMRig Automation
License: MIT
"""

import time
from dataclasses import dataclass, field
from typing import Tuple, Optional, Callable, List
from collections import deque


# ============================================================================
# CONFIGURATION
# ============================================================================

@dataclass
class ThermalConfig:
    """Configuration for thermal prediction."""
    max_temp: float = 85.0          # Maximum allowed temperature
    target_temp: float = 75.0       # Target operating temperature
    warning_buffer: float = 5.0     # Degrees before max to start throttling
    recovery_buffer: float = 10.0   # Degrees below target to allow recovery
    prediction_horizon: int = 10    # Seconds to predict ahead
    window_size: int = 30           # Number of samples in sliding window
    min_samples: int = 5            # Minimum samples before predictions


# ============================================================================
# THERMAL PREDICTOR
# ============================================================================

@dataclass
class ThermalPredictor:
    """
    Predicts temperature trajectory using linear regression.
    
    Uses a sliding window of temperature readings to predict
    future temperature and enable preemptive throttling.
    """
    config: ThermalConfig = field(default_factory=ThermalConfig)
    temperatures: deque = field(default_factory=lambda: deque(maxlen=30))
    timestamps: deque = field(default_factory=lambda: deque(maxlen=30))
    
    def __post_init__(self):
        self.temperatures = deque(maxlen=self.config.window_size)
        self.timestamps = deque(maxlen=self.config.window_size)
    
    def update(self, temp: float, timestamp: float = None) -> None:
        """
        Add new temperature reading.
        
        Args:
            temp: Current temperature in Celsius
            timestamp: Unix timestamp (default: current time)
        """
        if timestamp is None:
            timestamp = time.time()
        
        self.temperatures.append(temp)
        self.timestamps.append(timestamp)
    
    def predict(self, seconds_ahead: int = None) -> float:
        """
        Predict temperature N seconds into the future.
        
        Uses simple linear regression on the sliding window.
        
        Args:
            seconds_ahead: Prediction horizon (default from config)
            
        Returns:
            Predicted temperature in Celsius
        """
        if len(self.temperatures) < self.config.min_samples:
            return self.temperatures[-1] if self.temperatures else 0.0
        
        if seconds_ahead is None:
            seconds_ahead = self.config.prediction_horizon
        
        # Normalize timestamps to start from 0
        t0 = self.timestamps[0]
        t = [ts - t0 for ts in self.timestamps]
        T = list(self.temperatures)
        
        n = len(t)
        
        # Linear regression: T = slope * t + intercept
        sum_t = sum(t)
        sum_T = sum(T)
        sum_tT = sum(ti * Ti for ti, Ti in zip(t, T))
        sum_t2 = sum(ti * ti for ti in t)
        
        denominator = n * sum_t2 - sum_t * sum_t
        if denominator == 0:
            return T[-1]
        
        slope = (n * sum_tT - sum_t * sum_T) / denominator
        intercept = (sum_T - slope * sum_t) / n
        
        # Predict future temperature
        future_t = t[-1] + seconds_ahead
        predicted = slope * future_t + intercept
        
        return predicted
    
    def should_throttle(self) -> Tuple[bool, float]:
        """
        Check if throttling will be needed soon.
        
        Returns:
            Tuple of (should_throttle: bool, predicted_temp: float)
        """
        if len(self.temperatures) < self.config.min_samples:
            return (False, self.temperatures[-1] if self.temperatures else 0.0)
        
        predicted = self.predict()
        threshold = self.config.max_temp - self.config.warning_buffer
        
        return (predicted > threshold, predicted)
    
    def can_recover(self) -> Tuple[bool, float]:
        """
        Check if conditions are safe to increase threads.
        
        Returns:
            Tuple of (can_recover: bool, current_temp: float)
        """
        if not self.temperatures:
            return (True, 0.0)
        
        current = self.temperatures[-1]
        recovery_threshold = self.config.target_temp - self.config.recovery_buffer
        
        # Also check trend isn't rising
        if len(self.temperatures) >= 5:
            recent_avg = sum(list(self.temperatures)[-5:]) / 5
            older_avg = sum(list(self.temperatures)[:5]) / 5
            rising = recent_avg > older_avg + 2  # Rising by more than 2°C
        else:
            rising = False
        
        return (current < recovery_threshold and not rising, current)
    
    @property
    def trend(self) -> str:
        """Get current temperature trend."""
        if len(self.temperatures) < 5:
            return "INSUFFICIENT_DATA"
        
        recent = list(self.temperatures)[-5:]
        older = list(self.temperatures)[:5]
        
        recent_avg = sum(recent) / len(recent)
        older_avg = sum(older) / len(older)
        
        diff = recent_avg - older_avg
        
        if diff > 3:
            return "RISING_FAST"
        elif diff > 1:
            return "RISING"
        elif diff < -3:
            return "FALLING_FAST"
        elif diff < -1:
            return "FALLING"
        return "STABLE"
    
    def reset(self) -> None:
        """Clear all readings."""
        self.temperatures.clear()
        self.timestamps.clear()


# ============================================================================
# THERMAL CONTROLLER
# ============================================================================

@dataclass
class ThermalController:
    """
    Integrates thermal prediction with thread management.
    
    Provides callbacks for thread adjustment and manages
    the throttle/recovery state machine.
    """
    predictor: ThermalPredictor = field(default_factory=ThermalPredictor)
    current_threads: int = 12
    min_threads: int = 4
    max_threads: int = 16
    throttle_step: int = 2
    recovery_step: int = 1
    is_throttling: bool = False
    last_adjustment_time: float = 0.0
    cooldown_seconds: float = 30.0
    
    # Callbacks
    on_throttle: Optional[Callable[[int], None]] = None
    on_recover: Optional[Callable[[int], None]] = None
    
    def update(self, temp: float) -> dict:
        """
        Process new temperature and return action.
        
        Args:
            temp: Current CPU temperature
            
        Returns:
            Dict with action, threads, and status info
        """
        self.predictor.update(temp)
        
        result = {
            'action': 'none',
            'threads': self.current_threads,
            'current_temp': temp,
            'predicted_temp': self.predictor.predict(),
            'trend': self.predictor.trend,
            'is_throttling': self.is_throttling
        }
        
        # Cooldown check
        now = time.time()
        if now - self.last_adjustment_time < self.cooldown_seconds:
            result['action'] = 'cooldown'
            return result
        
        # Check if we need to throttle
        should_throttle, predicted = self.predictor.should_throttle()
        result['predicted_temp'] = predicted
        
        if should_throttle and self.current_threads > self.min_threads:
            # Throttle down
            new_threads = max(self.min_threads, self.current_threads - self.throttle_step)
            
            if new_threads != self.current_threads:
                self.current_threads = new_threads
                self.is_throttling = True
                self.last_adjustment_time = now
                
                result['action'] = 'throttle'
                result['threads'] = new_threads
                
                if self.on_throttle:
                    self.on_throttle(new_threads)
        
        elif not should_throttle and self.is_throttling:
            # Check if we can recover
            can_recover, current = self.predictor.can_recover()
            
            if can_recover and self.current_threads < self.max_threads:
                new_threads = min(self.max_threads, self.current_threads + self.recovery_step)
                
                if new_threads != self.current_threads:
                    self.current_threads = new_threads
                    self.last_adjustment_time = now
                    
                    # Check if fully recovered
                    if new_threads >= self.max_threads:
                        self.is_throttling = False
                    
                    result['action'] = 'recover'
                    result['threads'] = new_threads
                    
                    if self.on_recover:
                        self.on_recover(new_threads)
        
        return result
    
    def force_throttle(self, threads: int) -> None:
        """Force immediate throttle to specific thread count."""
        self.current_threads = max(self.min_threads, min(self.max_threads, threads))
        self.is_throttling = True
        self.last_adjustment_time = time.time()
    
    def reset(self) -> None:
        """Reset controller state."""
        self.predictor.reset()
        self.is_throttling = False
        self.current_threads = self.max_threads


# ============================================================================
# SELF-TEST
# ============================================================================

if __name__ == "__main__":
    print("\n" + "="*60)
    print("  THERMAL PREDICTION - SIMULATION TEST")
    print("="*60 + "\n")
    
    # Simulate rising temperature scenario
    controller = ThermalController(
        max_threads=8,
        min_threads=2
    )
    
    # Simulate temperature rising from 70°C to 88°C
    temps = [70, 72, 74, 76, 78, 80, 82, 84, 86, 88, 85, 82, 78, 74, 70]
    
    print("  Time  Temp   Predicted   Action      Threads  Trend")
    print("  ----  ----   ---------   ------      -------  -----")
    
    for i, temp in enumerate(temps):
        result = controller.update(temp)
        
        action_str = result['action'].upper().ljust(10)
        if result['action'] == 'throttle':
            action_str = f"\033[91m{action_str}\033[0m"
        elif result['action'] == 'recover':
            action_str = f"\033[92m{action_str}\033[0m"
        
        print(f"  T+{i:02d}   {temp:4.1f}°C   {result['predicted_temp']:5.1f}°C     "
              f"{action_str}  {result['threads']:2d}       {result['trend']}")
        
        # Small delay between updates (simulated)
        controller.last_adjustment_time -= 25  # Speed up cooldown for demo
    
    print("\n" + "="*60)
    print("  ✓ Simulation complete")
    print("="*60 + "\n")
