"""
XMRig Automation - Centralized Port Configuration
==================================================
Centralized port configuration to avoid conflicts with other Docker projects.

All ports use unique sequence in 20000-29999 range to avoid conflicts.
Pattern: 24XXX (XR = XMRig, 8 = Mining, 08 = Rig)

Author: XMRig Automation
License: MIT
"""

# ============================================================================
# UNIQUE PORT SEQUENCE (20000-29999 range)
# ============================================================================

# XMRig HTTP API (was 8080)
XMRIG_HTTP_PORT = 24808

# Prometheus Metrics (was 9100)
PROMETHEUS_METRICS_PORT = 29100

# Dashboard Web Server (future use)
DASHBOARD_WEB_PORT = 23000

# Alternative/Backup ports (future use)
XMRIG_API_ALT_PORT = 24809
METRICS_ALT_PORT = 29101

# ============================================================================
# PORT VALIDATION
# ============================================================================

def validate_ports():
    """Validate that ports are in safe range and not conflicting."""
    ports = [
        XMRIG_HTTP_PORT,
        PROMETHEUS_METRICS_PORT,
        DASHBOARD_WEB_PORT,
        XMRIG_API_ALT_PORT,
        METRICS_ALT_PORT
    ]

    # Check range
    for port in ports:
        if not (20000 <= port <= 29999):
            raise ValueError(f"Port {port} is not in safe range 20000-29999")

    # Check uniqueness
    if len(ports) != len(set(ports)):
        raise ValueError("Duplicate ports detected")

    print("✓ All ports validated successfully")
    return True

# ============================================================================
# CONFIGURATION EXPORTS
# ============================================================================

# Export for use in other modules
__all__ = [
    'XMRIG_HTTP_PORT',
    'PROMETHEUS_METRICS_PORT',
    'DASHBOARD_WEB_PORT',
    'XMRIG_API_ALT_PORT',
    'METRICS_ALT_PORT',
    'validate_ports'
]

# ============================================================================
# SELF-TEST
# ============================================================================

if __name__ == "__main__":
    print("\n" + "="*60)
    print("  XMRIG PORT CONFIGURATION")
    print("="*60 + "\n")

    print("  Port Assignments:")
    print(f"  XMRig HTTP API:     {XMRIG_HTTP_PORT}")
    print(f"  Prometheus Metrics: {PROMETHEUS_METRICS_PORT}")
    print(f"  Dashboard Web:      {DASHBOARD_WEB_PORT}")
    print(f"  XMRig API Alt:      {XMRIG_API_ALT_PORT}")
    print(f"  Metrics Alt:        {METRICS_ALT_PORT}")

    print("\n  Validation:")
    try:
        validate_ports()
        print("  ✓ All ports are valid and unique")
    except ValueError as e:
        print(f"  ✗ Validation failed: {e}")

    print("\n" + "="*60)
    print("  Configuration complete")
    print("="*60 + "\n")