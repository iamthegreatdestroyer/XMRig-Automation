"""
Prometheus Metrics Endpoint - Mining Observability
===================================================
Exposes XMRig mining metrics in Prometheus format for 
Grafana dashboards and alerting.

Features:
- Standard Prometheus metrics format
- Gauges for current values (hashrate, temp)
- Counters for cumulative values (shares)
- Built-in HTTP server on configurable port

Author: XMRig Automation
License: MIT
"""

import time
import threading
import http.server
import socketserver
from dataclasses import dataclass, field
from typing import Dict, Optional
from collections import defaultdict


# ============================================================================
# METRICS TYPES
# ============================================================================

class MetricType:
    GAUGE = "gauge"
    COUNTER = "counter"


@dataclass
class Metric:
    """Single metric with labels."""
    name: str
    help_text: str
    metric_type: str
    labels: Dict[str, str] = field(default_factory=dict)
    value: float = 0.0
    
    def prometheus_format(self) -> str:
        """Format as Prometheus exposition."""
        label_str = ""
        if self.labels:
            pairs = [f'{k}="{v}"' for k, v in self.labels.items()]
            label_str = "{" + ",".join(pairs) + "}"
        
        return f"{self.name}{label_str} {self.value}"


# ============================================================================
# METRICS REGISTRY
# ============================================================================

class MetricsRegistry:
    """Thread-safe metrics registry."""
    
    def __init__(self):
        self._metrics: Dict[str, Metric] = {}
        self._lock = threading.Lock()
    
    def gauge(self, name: str, help_text: str, labels: Dict[str, str] = None) -> 'GaugeMetric':
        """Create or get a gauge metric."""
        return GaugeMetric(self, name, help_text, labels or {})
    
    def counter(self, name: str, help_text: str, labels: Dict[str, str] = None) -> 'CounterMetric':
        """Create or get a counter metric."""
        return CounterMetric(self, name, help_text, labels or {})
    
    def _set_metric(self, name: str, metric: Metric):
        with self._lock:
            self._metrics[name] = metric
    
    def _get_key(self, name: str, labels: Dict[str, str]) -> str:
        label_str = ",".join(f"{k}={v}" for k, v in sorted(labels.items()))
        return f"{name}|{label_str}"
    
    def render(self) -> str:
        """Render all metrics in Prometheus format."""
        with self._lock:
            lines = []
            seen_help = set()
            
            for key, metric in sorted(self._metrics.items()):
                name = metric.name
                
                # Add HELP and TYPE only once per metric name
                if name not in seen_help:
                    lines.append(f"# HELP {name} {metric.help_text}")
                    lines.append(f"# TYPE {name} {metric.metric_type}")
                    seen_help.add(name)
                
                lines.append(metric.prometheus_format())
            
            return "\n".join(lines) + "\n"


class GaugeMetric:
    """Gauge metric (can go up and down)."""
    
    def __init__(self, registry: MetricsRegistry, name: str, help_text: str, labels: Dict[str, str]):
        self._registry = registry
        self._name = name
        self._help_text = help_text
        self._labels = labels
    
    def labels(self, **kwargs) -> 'GaugeMetric':
        """Return new gauge with additional labels."""
        new_labels = {**self._labels, **kwargs}
        return GaugeMetric(self._registry, self._name, self._help_text, new_labels)
    
    def set(self, value: float):
        """Set gauge value."""
        key = self._registry._get_key(self._name, self._labels)
        metric = Metric(
            name=self._name,
            help_text=self._help_text,
            metric_type=MetricType.GAUGE,
            labels=self._labels,
            value=value
        )
        self._registry._set_metric(key, metric)


class CounterMetric:
    """Counter metric (only goes up)."""
    
    def __init__(self, registry: MetricsRegistry, name: str, help_text: str, labels: Dict[str, str]):
        self._registry = registry
        self._name = name
        self._help_text = help_text
        self._labels = labels
        self._value = 0.0
    
    def labels(self, **kwargs) -> 'CounterMetric':
        """Return new counter with additional labels."""
        new_labels = {**self._labels, **kwargs}
        return CounterMetric(self._registry, self._name, self._help_text, new_labels)
    
    def inc(self, amount: float = 1.0):
        """Increment counter."""
        self._value += amount
        key = self._registry._get_key(self._name, self._labels)
        metric = Metric(
            name=self._name,
            help_text=self._help_text,
            metric_type=MetricType.COUNTER,
            labels=self._labels,
            value=self._value
        )
        self._registry._set_metric(key, metric)


# ============================================================================
# MINING METRICS
# ============================================================================

class MiningMetrics:
    """Pre-defined mining metrics."""
    
    def __init__(self, registry: MetricsRegistry = None):
        self.registry = registry or MetricsRegistry()
        
        # Gauges
        self.hashrate = self.registry.gauge(
            "xmrig_hashrate_hs",
            "Current hashrate in H/s"
        )
        self.cpu_temp = self.registry.gauge(
            "xmrig_cpu_temperature_celsius",
            "CPU temperature in Celsius"
        )
        self.pool_latency = self.registry.gauge(
            "xmrig_pool_latency_ms",
            "Pool latency in milliseconds"
        )
        self.profit_rate = self.registry.gauge(
            "xmrig_profit_rate_usd",
            "Estimated profit rate in USD/day"
        )
        self.health_score = self.registry.gauge(
            "xmrig_health_score",
            "Hardware health score 0-100"
        )
        self.threads = self.registry.gauge(
            "xmrig_threads_active",
            "Number of active mining threads"
        )
        self.difficulty = self.registry.gauge(
            "xmrig_difficulty",
            "Current mining difficulty"
        )
        
        # Counters
        self.shares_accepted = self.registry.counter(
            "xmrig_shares_total",
            "Total shares submitted"
        ).labels(status="accepted")
        
        self.shares_rejected = self.registry.counter(
            "xmrig_shares_total",
            "Total shares submitted"
        ).labels(status="rejected")
        
        self.coin_switches = self.registry.counter(
            "xmrig_coin_switches_total",
            "Total coin switches"
        )
        
        self.errors = self.registry.counter(
            "xmrig_errors_total",
            "Total errors encountered"
        )
    
    def update(self, data: dict):
        """Update all metrics from mining data dict."""
        if 'hashrate' in data:
            self.hashrate.labels(algorithm=data.get('algorithm', 'rx/0')).set(data['hashrate'])
        
        if 'cpu_temp' in data:
            self.cpu_temp.set(data['cpu_temp'])
        
        if 'pool_latency' in data:
            self.pool_latency.labels(pool=data.get('pool', 'unknown')).set(data['pool_latency'])
        
        if 'profit_rate' in data:
            self.profit_rate.labels(coin=data.get('coin', 'XMR')).set(data['profit_rate'])
        
        if 'health_score' in data:
            self.health_score.set(data['health_score'])
        
        if 'threads' in data:
            self.threads.set(data['threads'])
        
        if 'difficulty' in data:
            self.difficulty.set(data['difficulty'])
        
        if 'new_accepted' in data:
            self.shares_accepted.inc(data['new_accepted'])
        
        if 'new_rejected' in data:
            self.shares_rejected.inc(data['new_rejected'])


# ============================================================================
# HTTP SERVER
# ============================================================================

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    """HTTP handler for /metrics endpoint."""
    
    registry: MetricsRegistry = None
    
    def do_GET(self):
        if self.path == '/metrics':
            content = self.registry.render().encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Content-Length', len(content))
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Suppress logging


class MetricsServer:
    """HTTP server for Prometheus scraping."""
    
    def __init__(self, registry: MetricsRegistry, port: int = 29100):
        self.registry = registry
        self.port = port
        self._server: Optional[socketserver.TCPServer] = None
        self._thread: Optional[threading.Thread] = None
    
    def start(self):
        """Start the metrics server."""
        handler = MetricsHandler
        handler.registry = self.registry
        
        self._server = socketserver.TCPServer(('', self.port), handler)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        print(f"[Prometheus] Metrics server started on port {self.port}")
    
    def stop(self):
        """Stop the metrics server."""
        if self._server:
            self._server.shutdown()


# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

_default_metrics: Optional[MiningMetrics] = None
_default_server: Optional[MetricsServer] = None


def start_metrics_server(port: int = 29100) -> MiningMetrics:
    """Start default metrics server and return metrics object."""
    global _default_metrics, _default_server
    
    registry = MetricsRegistry()
    _default_metrics = MiningMetrics(registry)
    _default_server = MetricsServer(registry, port)
    _default_server.start()
    
    return _default_metrics


def get_metrics() -> Optional[MiningMetrics]:
    """Get default metrics object."""
    return _default_metrics


# ============================================================================
# SELF-TEST
# ============================================================================

if __name__ == "__main__":
    print("\n" + "="*60)
    print("  PROMETHEUS METRICS - TEST")
    print("="*60 + "\n")
    
    # Start server
    metrics = start_metrics_server(port=9100)
    
    # Update some metrics
    metrics.hashrate.labels(algorithm="rx/0").set(4500)
    metrics.cpu_temp.set(72.5)
    metrics.shares_accepted.inc(10)
    metrics.shares_rejected.inc(1)
    metrics.pool_latency.labels(pool="hashvault").set(45)
    metrics.health_score.set(85)
    
    # Print rendered output
    print("  Metrics output:")
    print("-" * 40)
    print(metrics.registry.render())
    
    print("\n  Server running on http://localhost:9100/metrics")
    print("  Press Ctrl+C to stop...")
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        _default_server.stop()
        print("\n  Server stopped.")
