"""
XMRig Streaming Log Parser - O(1) Amortized Complexity
=======================================================
High-performance streaming parser with Welford statistics and change detection.

Performance: O(1) amortized parsing, O(1) statistics, O(1) change detection.
Integration: mining-dashboard.py via create_optimized_reader() factory.
"""
from __future__ import annotations
import os
import re
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Dict, Any, Tuple


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
    Detects log rotation via inode changes or size shrinkage.
    Pre-compiled regex patterns eliminate per-call compilation.
    
    Example:
        >>> parser = OptimizedLogParser("/path/to/xmrig.log")
        >>> data = parser.read_new()
        >>> print(f"Hashrate: {data['hashrate_60s']} H/s")
    """
    log_path: str
    _pos: int = field(default=0, repr=False)
    _inode: int = field(default=0, repr=False)
    _buf_size: int = field(default=8192, repr=False)
    
    # Pre-compiled regex patterns (class-level, zero per-instance cost)
    _RE_SPD: re.Pattern = field(default=re.compile(r'speed.*?(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s*H/s'), repr=False)
    _RE_SHR: re.Pattern = field(default=re.compile(r'accepted \((\d+)/(\d+)\)'), repr=False)
    _RE_POOL: re.Pattern = field(default=re.compile(r'new job from ([^\s]+)'), repr=False)
    _RE_ALGO: re.Pattern = field(default=re.compile(r'algo\s+(\S+)'), repr=False)
    _RE_DIFF: re.Pattern = field(default=re.compile(r'diff\s+(\d+)'), repr=False)
    
    _cache: Dict[str, Any] = field(default_factory=lambda: {
        'hashrate_10s': 0.0, 'hashrate_60s': 0.0, 'hashrate_15m': 0.0,
        'accepted': 0, 'rejected': 0, 'pool': 'N/A', 'algo': 'N/A', 'diff': 0
    }, repr=False)

    def read_new(self) -> Dict[str, Any]:
        """Read only new content since last call - O(1) amortized."""
        if not os.path.exists(self.log_path):
            return self._cache.copy()
        try:
            size = os.path.getsize(self.log_path)
            inode = getattr(os.stat(self.log_path), 'st_ino', 0)
            
            # Detect rotation (inode change or shrink)
            if inode != self._inode or size < self._pos:
                self._pos, self._inode = 0, inode
            
            if size <= self._pos:  # No new data - fast path
                return self._cache.copy()
            
            start = max(self._pos, size - self._buf_size)
            with open(self.log_path, 'rb') as f:
                f.seek(start)
                chunk = f.read(size - start).decode('utf-8', errors='ignore')
            self._pos = size
            self._parse(chunk)
        except OSError:
            pass
        return self._cache.copy()

    def _parse(self, text: str) -> None:
        """Parse with pre-compiled patterns and early exit."""
        lines, fspd, fshr = text.strip().split('\n')[-50:], False, False
        for ln in reversed(lines):
            if fspd and fshr: break
            if not fspd and 'speed' in ln and (m := self._RE_SPD.search(ln)):
                self._cache.update(hashrate_10s=float(m[1]), hashrate_60s=float(m[2]), hashrate_15m=float(m[3] or 0))
                fspd = True
            if not fshr and 'accepted' in ln:
                if m := self._RE_SHR.search(ln):
                    self._cache.update(accepted=int(m[1]), rejected=int(m[2]))
                    fshr = True
                if m := self._RE_DIFF.search(ln):
                    self._cache['diff'] = int(m[1])
            if self._cache['pool'] == 'N/A' and 'new job' in ln:
                if m := self._RE_POOL.search(ln): self._cache['pool'] = m[1]
                if m := self._RE_ALGO.search(ln): self._cache['algo'] = m[1]


@dataclass
class StreamingStats:
    """
    O(1) online statistics: Welford's algorithm + exponential moving average.
    
    Memory: O(1) constant. No unbounded sample storage.
    
    Example:
        >>> stats = StreamingStats()
        >>> for hr in hashrates: stats.update(hr)
        >>> print(f"Mean: {stats.mean:.2f}, Trend: {stats.trend}")
    """
    _n: int = 0
    _mean: float = 0.0
    _m2: float = 0.0
    _ema: float = 0.0
    _prev_ema: float = 0.0
    _alpha: float = 0.2
    _thresh: float = 0.02

    @property
    def mean(self) -> float: return self._mean
    
    @property
    def variance(self) -> float: return self._m2 / (self._n - 1) if self._n > 1 else 0.0
    
    @property
    def std(self) -> float: return self.variance ** 0.5
    
    @property
    def ema(self) -> float: return self._ema
    
    @property
    def trend(self) -> Trend:
        if self._n < 2: return Trend.STABLE
        d = (self._ema - self._prev_ema) / max(self._prev_ema, 1e-9)
        return Trend.RISING if d > self._thresh else Trend.FALLING if d < -self._thresh else Trend.STABLE

    def update(self, v: float) -> 'StreamingStats':
        """Update with new sample - O(1)."""
        self._n += 1
        d = v - self._mean
        self._mean += d / self._n
        self._m2 += d * (v - self._mean)
        self._prev_ema = self._ema
        self._ema = v if self._n == 1 else self._alpha * v + (1 - self._alpha) * self._ema
        return self

    def reset(self) -> None:
        self._n = 0
        self._mean = self._m2 = self._ema = self._prev_ema = 0.0


@dataclass
class ChangeDetectingBuffer:
    """
    Minimize UI repaints by detecting significant value changes.
    
    Only reports changes exceeding relative tolerance threshold.
    
    Example:
        >>> buf = ChangeDetectingBuffer(tolerance=0.01)
        >>> if buf.update("hashrate", 1234.5):
        ...     update_ui(buf.get("hashrate"))
    """
    tolerance: float = 0.01
    _vals: Dict[str, float] = field(default_factory=dict)
    _updates: int = 0
    _changes: int = 0

    def update(self, key: str, val: float) -> bool:
        """Return True if change exceeds tolerance (UI should repaint)."""
        self._updates += 1
        prev = self._vals.get(key)
        if prev is None or abs(val - prev) / max(abs(prev), 1e-9) > self.tolerance:
            self._vals[key] = val
            self._changes += 1
            return True
        return False

    def get(self, key: str, default: float = 0.0) -> float:
        return self._vals.get(key, default)

    @property
    def efficiency(self) -> float:
        """Ratio of skipped updates (higher = more efficient)."""
        return 1 - (self._changes / max(self._updates, 1))

    @property
    def metrics(self) -> Dict[str, Any]:
        return {'updates': self._updates, 'changes': self._changes, 
                'skipped': self._updates - self._changes, 'efficiency_pct': self.efficiency * 100}


def create_optimized_reader(log_path: str) -> Tuple[OptimizedLogParser, StreamingStats, ChangeDetectingBuffer]:
    """Factory for dashboard integration. Returns parser, stats, and change buffer."""
    return OptimizedLogParser(log_path), StreamingStats(), ChangeDetectingBuffer(tolerance=0.005)
