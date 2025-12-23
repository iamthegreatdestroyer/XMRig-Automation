"""Quick test for streaming_parser module."""
from streaming_parser import OptimizedLogParser, StreamingStats, ChangeDetectingBuffer, Trend, create_optimized_reader

# Test StreamingStats with Welford's algorithm
s = StreamingStats()
for v in [100, 102, 98, 101, 99]:
    s.update(v)
print(f"StreamingStats: mean={s.mean:.2f}, std={s.std:.2f}, ema={s.ema:.2f}, trend={s.trend}")
assert abs(s.mean - 100) < 0.1, "Mean should be ~100"
assert s.trend == Trend.STABLE, "Trend should be stable"

# Test ChangeDetectingBuffer
b = ChangeDetectingBuffer(tolerance=0.01)
r1 = b.update("hr", 100)      # First value - always True
r2 = b.update("hr", 100.5)    # 0.5% change < 1% tolerance - False
r3 = b.update("hr", 110)      # 10% change > 1% tolerance - True
print(f"Buffer: {r1=}, {r2=}, {r3=}")
print(f"Efficiency: {b.efficiency:.1%}, metrics={b.metrics}")
assert r1 == True and r2 == False and r3 == True

# Test OptimizedLogParser (mock path)
p = OptimizedLogParser("nonexistent.log")
data = p.read_new()
print(f"Parser cache (no file): hashrate_60s={data['hashrate_60s']}")
assert data["hashrate_60s"] == 0.0

# Test factory
parser, stats, buf = create_optimized_reader("test.log")
print(f"Factory OK: {type(parser).__name__}, {type(stats).__name__}, {type(buf).__name__}")

print("\n✓ All tests passed!")
