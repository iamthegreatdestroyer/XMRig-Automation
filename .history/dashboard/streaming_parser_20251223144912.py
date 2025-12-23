"""
XMRig Streaming Log Parser - O(1) Amortized Complexity
=======================================================
High-performance streaming parser for XMRig mining logs with:
- Seek-based incremental reads (O(1) amortized)
- Log rotation detection via inode tracking
- Welford's algorithm for online statistics
- Change-detecting buffer for minimal UI updates

Author: @VELOCITY - Elite Agent Collective
Integration: mining-dashboard.py

Performance Characteristics:
    - Log parsing: O(1) amortized (constant buffer reads)
    - Statistics update: O(1) per sample (Welford's algorithm)
    - Change detection: O(1) per value check
    - Memory: O(1) constant (no unbounded growth)
"""

from __future__ import annotations
import os
import re
import time
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional, Dict, Any, Tuple


class Trend(Enum):
    """Trend direction for streaming statistics."""
    RISING = auto()
    FALLING = auto()
    STABLE = auto()


@dataclass
class OptimizedLogParser:
    """
    O(1) amortized streaming log parser with rotation detection.
    
    Uses seek-based reads to parse only new content since last read.
    Detects log rotation via inode changes (Windows: file ID fallback).
    Pre-compiled regex patterns eliminate compilation overhead.
    
    Example:
        >>> parser = OptimizedLogParser("/path/to/xmrig.log")
        >>> data = parser.read_new()
        >>> print(f"Hashrate: {data['hashrate_60s']} H/s")
    """
    log_path: str
    _position: int = field(default=0, repr=False)
    _inode: int = field(default=0, repr=False)
    _buffer_size: int = field(default=8192, repr=False)  # 8KB constant
    
    # Pre-compiled patterns - class-level for zero per-instance cost
    _RE_SPEED: re.Pattern = field(
        default=re.compile(r'speed.*?(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s*H/s'),
        repr=False
    )
    _RE_SHARES: re.Pattern = field(
        default=re.compile(r'accepted \((\d+)/(\d+)\)'),
        repr=False
    )
    _RE_POOL: re.Pattern = field(
        default=re.compile(r'new job from ([^\s]+)'),
        repr=False
    )
    _RE_ALGO: re.Pattern = field(
        default=re.compile(r'algo\s+(\S+)'),
        repr=False
    )
    _RE_DIFF: re.Pattern = field(
        default=re.compile(r'diff\s+(\d+)'),
        repr=False
    )
    
    # Cached state
    _cache: Dict[str, Any] = field(default_factory=lambda: {
        'hashrate_10s': 0.0, 'hashrate_60s': 0.0, 'hashrate_15m': 0.0,
        'accepted': 0, 'rejected': 0, 'pool': 'N/A', 'algo': 'N/A', 'diff': 0
    }, repr=False)
    
    def _get_inode(self) -> int:
        """Get file inode (Windows: uses file index as fallback)."""
        try:
            stat = os.stat(self.log_path)
            return getattr(stat, 'st_ino', 0) or hash(self.log_path)
        except OSError:
            return 0
    
    def _detect_rotation(self, current_size: int) -> bool:
        """Detect log rotation via inode change or size shrink."""
        current_inode = self._get_inode()
        rotated = (current_inode != self._inode) or (current_size < self._position)
        if rotated:
            self._position = 0
            self._inode = current_inode
        return rotated
    
    def read_new(self) -> Dict[str, Any]:
        """
        Read only new content since last call - O(1) amortized.
        
        Returns cached state if no new data. Resets on rotation.
        """
        if not os.path.exists(self.log_path):
            return self._cache.copy()
        
        try:
            size = os.path.getsize(self.log_path)
            self._detect_rotation(size)
            
            # No new data - return cached state (O(1) fast path)
            if size <= self._position:
                return self._cache.copy()
            
            # Calculate read window - bounded constant
            read_start = max(self._position, size - self._buffer_size)
            bytes_to_read = size - read_start
            
            with open(self.log_path, 'rb') as f:
                f.seek(read_start)
                chunk = f.read(bytes_to_read).decode('utf-8', errors='ignore')
            
            self._position = size
            self._parse_chunk(chunk)
            return self._cache.copy()
            
        except (OSError, IOError):
            return self._cache.copy()
    
    def _parse_chunk(self, text: str) -> None:
        """Parse chunk with pre-compiled patterns and early exit."""
        lines = text.strip().split('\n')[-50:]  # Last 50 lines max
        found_speed = found_shares = False
        
        for line in reversed(lines):
            if found_speed and found_shares:
                break  # Early exit once we have key metrics
            
            if not found_speed and 'speed' in line:
                if m := self._RE_SPEED.search(line):
                    self._cache['hashrate_10s'] = float(m.group(1))
                    self._cache['hashrate_60s'] = float(m.group(2))
                    self._cache['hashrate_15m'] = float(m.group(3) or 0)
                    found_speed = True
            
            if not found_shares and 'accepted' in line:
                if m := self._RE_SHARES.search(line):
                    self._cache['accepted'] = int(m.group(1))
                    self._cache['rejected'] = int(m.group(2))
                    found_shares = True
                if m := self._RE_DIFF.search(line):
                    self._cache['diff'] = int(m.group(1))
            
            if self._cache['pool'] == 'N/A' and 'new job from' in line:
                if m := self._RE_POOL.search(line):
                    self._cache['pool'] = m.group(1)
                if m := self._RE_ALGO.search(line):
                    self._cache['algo'] = m.group(1)


@dataclass
class StreamingStats:
    """
    O(1) online statistics using Welford's algorithm + EMA.
    
    Computes running mean, variance, and trend without storing samples.
    Memory: O(1) constant regardless of sample count.
    
    Example:
        >>> stats = StreamingStats()
        >>> for hr in hashrates:
        ...     stats.update(hr)
        >>> print(f"Mean: {stats.mean:.2f}, Trend: {stats.trend}")
    """
    # Welford's algorithm state
    _n: int = 0
    _mean: float = 0.0
    _m2: float = 0.0  # Sum of squared differences
    
    # Exponential moving average state
    _ema: float = 0.0
    _ema_alpha: float = 0.2  # Smoothing factor (higher = more responsive)
    _prev_ema: float = 0.0
    
    # Trend detection
    _trend_threshold: float = 0.02  # 2% change threshold
    
    @property
    def mean(self) -> float:
        """Current running mean."""
        return self._mean
    
    @property
    def variance(self) -> float:
        """Current sample variance (Bessel-corrected)."""
        return self._m2 / (self._n - 1) if self._n > 1 else 0.0
    
    @property
    def std(self) -> float:
        """Current standard deviation."""
        return self.variance ** 0.5
    
    @property
    def ema(self) -> float:
        """Exponential moving average."""
        return self._ema
    
    @property
    def trend(self) -> Trend:
        """Detect trend direction based on EMA change."""
        if self._n < 2:
            return Trend.STABLE
        delta = (self._ema - self._prev_ema) / max(self._prev_ema, 1e-9)
        if delta > self._trend_threshold:
            return Trend.RISING
        elif delta < -self._trend_threshold:
            return Trend.FALLING
        return Trend.STABLE
    
    def update(self, value: float) -> 'StreamingStats':
        """Update statistics with new sample - O(1)."""
        self._n += 1
        
        # Welford's online algorithm
        delta = value - self._mean
        self._mean += delta / self._n
        delta2 = value - self._mean
        self._m2 += delta * delta2
        
        # EMA update
        self._prev_ema = self._ema
        if self._n == 1:
            self._ema = value
        else:
            self._ema = self._ema_alpha * value + (1 - self._ema_alpha) * self._ema
        
        return self
    
    def reset(self) -> None:
        """Reset all statistics."""
        self._n = 0
        self._mean = self._m2 = self._ema = self._prev_ema = 0.0


@dataclass
class ChangeDetectingBuffer:
    """
    Minimizes UI repaints by detecting significant value changes.
    
    Only reports changes exceeding tolerance threshold.
    Tracks efficiency metrics for optimization analysis.
    
    Example:
        >>> buf = ChangeDetectingBuffer(tolerance=0.01)
        >>> if buf.update("hashrate", 1234.5):
        ...     update_ui(buf.get("hashrate"))  # Only when changed
    """
    tolerance: float = 0.01  # 1% change threshold
    _values: Dict[str, float] = field(default_factory=dict)
    _update_count: int = 0
    _change_count: int = 0
    
    def update(self, key: str, value: float) -> bool:
        """
        Update value and return True if change exceeds tolerance.
        
        Returns:
            True if UI should repaint, False to skip
        """
        self._update_count += 1
        prev = self._values.get(key)
        
        if prev is None:
            self._values[key] = value
            self._change_count += 1
            return True
        
        # Relative tolerance check (handles varying magnitudes)
        rel_delta = abs(value - prev) / max(abs(prev), 1e-9)
        
        if rel_delta > self.tolerance:
            self._values[key] = value
            self._change_count += 1
            return True
        
        return False
    
    def get(self, key: str, default: float = 0.0) -> float:
        """Get current value for key."""
        return self._values.get(key, default)
    
    @property
    def efficiency(self) -> float:
        """Ratio of skipped updates (higher = more efficient)."""
        if self._update_count == 0:
            return 1.0
        return 1 - (self._change_count / self._update_count)
    
    @property
    def metrics(self) -> Dict[str, Any]:
        """Get efficiency metrics for analysis."""
        return {
            'total_updates': self._update_count,
            'actual_changes': self._change_count,
            'skipped': self._update_count - self._change_count,
            'efficiency_pct': self.efficiency * 100
        }


# =============================================================================
# Integration Helper
# =============================================================================

def create_optimized_reader(log_path: str) -> Tuple[
    OptimizedLogParser, StreamingStats, ChangeDetectingBuffer
]:
    """
    Factory function for dashboard integration.
    
    Returns pre-configured parser, stats tracker, and change buffer.
    """
    return (
        OptimizedLogParser(log_path),
        StreamingStats(),
        ChangeDetectingBuffer(tolerance=0.005)  # 0.5% for hashrate
    )
