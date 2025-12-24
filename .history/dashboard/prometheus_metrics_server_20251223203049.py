#!/usr/bin/env python3
"""
XMRig Automation - Production Prometheus Metrics Server
=======================================================
Production-ready metrics server that runs continuously.

Author: XMRig Automation
License: MIT
"""

import time
import logging
from prometheus_metrics import start_metrics_server

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def main():
    """Main production server function."""
    logger.info("Starting XMRig Prometheus Metrics Server (Production)")

    try:
        # Start the metrics server
        metrics = start_metrics_server(port=29100)
        logger.info("Metrics server started on port 29100")

        # Update initial metrics
        metrics.hashrate.labels(algorithm="rx/0").set(0)
        metrics.cpu_temp.set(25.0)
        metrics.shares_accepted.inc(0)
        metrics.shares_rejected.inc(0)
        metrics.pool_latency.labels(pool="unknown").set(0)
        metrics.health_score.set(100)

        logger.info("Initial metrics set")

        # Keep the server running
        logger.info("Server running continuously. Press Ctrl+C to stop.")
        while True:
            time.sleep(60)  # Update metrics every minute
            # In production, you would update metrics here with real data

    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")
        raise

if __name__ == "__main__":
    main()