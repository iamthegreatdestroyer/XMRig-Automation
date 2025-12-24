"""
XMRig HTTP API Client
=====================
Direct API access to XMRig miner for real-time statistics.

Features:
- Async-ready HTTP client
- Automatic token authentication
- Cached connection with timeout handling
- Integration with dashboard and event bus

Author: XMRig Automation
License: MIT
"""

import json
import time
from dataclasses import dataclass, field
from typing import Dict, Optional, Any
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError


# ============================================================================
# DATA STRUCTURES
# ============================================================================

@dataclass
class XMRigSummary:
    """Parsed summary from XMRig API."""
    hashrate_10s: float = 0.0
    hashrate_60s: float = 0.0
    hashrate_15m: float = 0.0
    hashrate_max: float = 0.0
    shares_accepted: int = 0
    shares_rejected: int = 0
    difficulty: int = 0
    algorithm: str = "unknown"
    pool_url: str = "unknown"
    uptime: int = 0
    version: str = "unknown"
    cpu_brand: str = "unknown"
    cpu_cores: int = 0
    threads: int = 0
    hugepages: bool = False
    memory_free: int = 0
    memory_total: int = 0
    
    @classmethod
    def from_api(cls, data: dict) -> 'XMRigSummary':
        """Parse from XMRig /2/summary response."""
        hashrate = data.get('hashrate', {}).get('total', [0, 0, 0, 0])
        
        return cls(
            hashrate_10s=hashrate[0] if len(hashrate) > 0 else 0,
            hashrate_60s=hashrate[1] if len(hashrate) > 1 else 0,
            hashrate_15m=hashrate[2] if len(hashrate) > 2 else 0,
            hashrate_max=data.get('hashrate', {}).get('highest', 0),
            shares_accepted=data.get('results', {}).get('shares_good', 0),
            shares_rejected=data.get('results', {}).get('shares_total', 0) - 
                           data.get('results', {}).get('shares_good', 0),
            difficulty=data.get('results', {}).get('diff_current', 0),
            algorithm=data.get('algo', 'unknown'),
            pool_url=data.get('connection', {}).get('pool', 'unknown'),
            uptime=data.get('uptime', 0),
            version=data.get('version', 'unknown'),
            cpu_brand=data.get('cpu', {}).get('brand', 'unknown'),
            cpu_cores=data.get('cpu', {}).get('cores', 0),
            threads=len(data.get('hashrate', {}).get('threads', [])),
            hugepages=data.get('hugepages', False),
            memory_free=data.get('resources', {}).get('memory', {}).get('free', 0),
            memory_total=data.get('resources', {}).get('memory', {}).get('total', 0),
        )
    
    def to_dict(self) -> dict:
        """Convert to dict for event bus / dashboard."""
        return {
            'hashrate': self.hashrate_60s,
            'hashrate_10s': self.hashrate_10s,
            'hashrate_60s': self.hashrate_60s,
            'hashrate_15m': self.hashrate_15m,
            'hashrate_max': self.hashrate_max,
            'accepted': self.shares_accepted,
            'rejected': self.shares_rejected,
            'difficulty': self.difficulty,
            'algorithm': self.algorithm,
            'pool': self.pool_url,
            'uptime': self.uptime,
            'threads': self.threads,
            'version': self.version,
        }


@dataclass
class XMRigBackends:
    """Parsed backends information."""
    cpu_enabled: bool = False
    cpu_threads: int = 0
    opencl_enabled: bool = False
    cuda_enabled: bool = False
    
    @classmethod
    def from_api(cls, data: list) -> 'XMRigBackends':
        """Parse from XMRig /2/backends response."""
        result = cls()
        for backend in data:
            backend_type = backend.get('type', '')
            if backend_type == 'cpu':
                result.cpu_enabled = backend.get('enabled', False)
                result.cpu_threads = len(backend.get('threads', []))
            elif backend_type == 'opencl':
                result.opencl_enabled = backend.get('enabled', False)
            elif backend_type == 'cuda':
                result.cuda_enabled = backend.get('enabled', False)
        return result


# ============================================================================
# API CLIENT
# ============================================================================

class XMRigAPIClient:
    """HTTP client for XMRig API."""
    
    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 24808,
        access_token: str = None,
        timeout: float = 5.0
    ):
        self.base_url = f"http://{host}:{port}"
        self.access_token = access_token
        self.timeout = timeout
        
        # Cache
        self._last_summary: Optional[XMRigSummary] = None
        self._last_fetch_time: float = 0
        self._cache_ttl: float = 1.0  # 1 second cache
    
    def _request(self, endpoint: str) -> dict:
        """Make authenticated request to API."""
        url = f"{self.base_url}{endpoint}"
        
        headers = {}
        if self.access_token:
            headers['Authorization'] = f'Bearer {self.access_token}'
        
        request = Request(url, headers=headers)
        
        try:
            with urlopen(request, timeout=self.timeout) as response:
                return json.loads(response.read().decode('utf-8'))
        except (URLError, HTTPError) as e:
            raise XMRigAPIError(f"API request failed: {e}")
    
    def get_summary(self, use_cache: bool = True) -> XMRigSummary:
        """Get miner summary."""
        now = time.time()
        
        if use_cache and self._last_summary and (now - self._last_fetch_time) < self._cache_ttl:
            return self._last_summary
        
        data = self._request('/2/summary')
        summary = XMRigSummary.from_api(data)
        
        self._last_summary = summary
        self._last_fetch_time = now
        
        return summary
    
    def get_backends(self) -> XMRigBackends:
        """Get backends information."""
        data = self._request('/2/backends')
        return XMRigBackends.from_api(data)
    
    def get_config(self) -> dict:
        """Get current configuration."""
        return self._request('/2/config')
    
    def pause(self) -> bool:
        """Pause mining."""
        try:
            self._request('/2/pause')
            return True
        except XMRigAPIError:
            return False
    
    def resume(self) -> bool:
        """Resume mining."""
        try:
            self._request('/2/resume')
            return True
        except XMRigAPIError:
            return False
    
    def is_running(self) -> bool:
        """Check if miner is running and responding."""
        try:
            self.get_summary(use_cache=False)
            return True
        except XMRigAPIError:
            return False


class XMRigAPIError(Exception):
    """Exception for API errors."""
    pass


# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

_default_client: Optional[XMRigAPIClient] = None


def get_client(
    host: str = "127.0.0.1",
    port: int = 24808,
    access_token: str = "xmrig-secure-token-2025"
) -> XMRigAPIClient:
    """Get or create default API client."""
    global _default_client
    
    if _default_client is None:
        _default_client = XMRigAPIClient(host, port, access_token)
    
    return _default_client


def get_mining_data() -> dict:
    """Get mining data in dashboard-compatible format."""
    client = get_client()
    
    try:
        summary = client.get_summary()
        return {
            'source': 'api',
            'connected': True,
            **summary.to_dict()
        }
    except XMRigAPIError:
        return {
            'source': 'api',
            'connected': False,
            'error': 'API not available'
        }


# ============================================================================
# SELF-TEST
# ============================================================================

if __name__ == "__main__":
    print("\n" + "="*60)
    print("  XMRIG API CLIENT - TEST")
    print("="*60 + "\n")
    
    client = XMRigAPIClient(
        host="127.0.0.1",
        port=24808,
        access_token="xmrig-secure-token-2025"
    )
    
    print(f"  Base URL: {client.base_url}")
    print(f"  Testing connection...")
    
    if client.is_running():
        print("  ✓ XMRig is running\n")
        
        summary = client.get_summary()
        print(f"  Hashrate (60s): {summary.hashrate_60s:.2f} H/s")
        print(f"  Shares: {summary.shares_accepted} accepted, {summary.shares_rejected} rejected")
        print(f"  Algorithm: {summary.algorithm}")
        print(f"  Pool: {summary.pool_url}")
        print(f"  Threads: {summary.threads}")
        print(f"  Uptime: {summary.uptime // 60} minutes")
        print(f"  Version: {summary.version}")
    else:
        print("  ✗ XMRig not responding")
        print("  Make sure XMRig is running with HTTP API enabled:")
        print('  "http": { "enabled": true, "port": 8080 }')
    
    print("\n" + "="*60)
    print("  Test complete")
    print("="*60 + "\n")
