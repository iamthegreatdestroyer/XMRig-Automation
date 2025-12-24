#!/usr/bin/env python3
"""
XMRig Automation - Production Web Dashboard
============================================
Web-based dashboard for production monitoring.

Author: XMRig Automation
License: MIT
"""

import sys
import os
import json
import time
import logging
from datetime import datetime
from flask import Flask, render_template_string, jsonify
from threading import Thread
import psutil

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from xmrig_api_client import get_client

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

class DashboardData:
    def __init__(self):
        self.xmrig_client = get_client()
        self.last_update = None
        self.cached_data = {}

    def update_data(self):
        """Update dashboard data from XMRig API."""
        try:
            summary = self.xmrig_client.get_summary()
            self.cached_data = {
                'hashrate': summary.hashrate_60s,
                'pool': summary.pool_url,
                'shares_accepted': summary.shares_accepted,
                'shares_rejected': summary.shares_rejected,
                'uptime': summary.uptime,
                'cpu_usage': psutil.cpu_percent(),
                'memory_usage': psutil.virtual_memory().percent,
                'timestamp': datetime.now().isoformat()
            }
            self.last_update = datetime.now()
            logger.info(f"Dashboard data updated: {self.cached_data['hashrate']} H/s")
        except Exception as e:
            logger.error(f"Failed to update dashboard data: {e}")

    def get_data(self):
        """Get current dashboard data."""
        return self.cached_data

# Global dashboard instance
dashboard = DashboardData()

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>XMRig Automation - Production Dashboard</title>
    <style>
        body {
            font-family: 'Courier New', monospace;
            background: #0a0a0a;
            color: #00ff00;
            margin: 0;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            border-bottom: 2px solid #00ff00;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .metric-card {
            background: #1a1a1a;
            border: 1px solid #333;
            border-radius: 8px;
            padding: 20px;
            text-align: center;
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #00ff00;
            margin: 10px 0;
        }
        .metric-label {
            font-size: 0.9em;
            color: #888;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .status {
            padding: 10px;
            border-radius: 4px;
            margin: 10px 0;
            font-weight: bold;
        }
        .status.online { background: #004400; color: #00ff00; }
        .status.offline { background: #440000; color: #ff4444; }
        .footer {
            text-align: center;
            color: #666;
            font-size: 0.8em;
            margin-top: 40px;
        }
        .refresh-info {
            color: #888;
            font-size: 0.8em;
        }
    </style>
    <script>
        function updateDashboard() {
            fetch('/api/data')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('hashrate').textContent = data.hashrate ? data.hashrate.toFixed(2) + ' H/s' : 'N/A';
                    document.getElementById('pool').textContent = data.pool || 'N/A';
                    document.getElementById('shares-accepted').textContent = data.shares_accepted || '0';
                    document.getElementById('shares-rejected').textContent = data.shares_rejected || '0';
                    document.getElementById('uptime').textContent = data.uptime ? Math.floor(data.uptime / 3600) + 'h ' + Math.floor((data.uptime % 3600) / 60) + 'm' : 'N/A';
                    document.getElementById('cpu-usage').textContent = data.cpu_usage ? data.cpu_usage.toFixed(1) + '%' : 'N/A';
                    document.getElementById('memory-usage').textContent = data.memory_usage ? data.memory_usage.toFixed(1) + '%' : 'N/A';
                    document.getElementById('last-update').textContent = data.timestamp || 'Never';

                    const statusEl = document.getElementById('status');
                    statusEl.textContent = data.hashrate ? 'ONLINE' : 'OFFLINE';
                    statusEl.className = 'status ' + (data.hashrate ? 'online' : 'offline');
                })
                .catch(error => {
                    console.error('Error updating dashboard:', error);
                    document.getElementById('status').textContent = 'ERROR';
                    document.getElementById('status').className = 'status offline';
                });
        }

        // Update every 5 seconds
        setInterval(updateDashboard, 5000);
        updateDashboard(); // Initial load
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 XMRIG AUTOMATION - PRODUCTION DASHBOARD</h1>
            <div id="status" class="status">LOADING...</div>
            <div class="refresh-info">Auto-refresh every 5 seconds</div>
        </div>

        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-label">Hashrate</div>
                <div id="hashrate" class="metric-value">--</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">Pool</div>
                <div id="pool" class="metric-value">--</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">Shares Accepted</div>
                <div id="shares-accepted" class="metric-value">--</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">Shares Rejected</div>
                <div id="shares-rejected" class="metric-value">--</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">Uptime</div>
                <div id="uptime" class="metric-value">--</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">CPU Usage</div>
                <div id="cpu-usage" class="metric-value">--</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">Memory Usage</div>
                <div id="memory-usage" class="metric-value">--</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">Last Update</div>
                <div id="last-update" class="metric-value">--</div>
            </div>
        </div>

        <div class="footer">
            <p>XMRig Automation v2.0 - Production Mode</p>
            <p>Ports: XMRig API (24808) | Prometheus Metrics (29100) | Dashboard (23000)</p>
        </div>
    </div>
</body>
</html>
"""

@app.route('/')
def index():
    """Serve the main dashboard page."""
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/data')
def api_data():
    """API endpoint for dashboard data."""
    return jsonify(dashboard.get_data())

def update_thread():
    """Background thread to update dashboard data."""
    while True:
        dashboard.update_data()
        time.sleep(30)  # Update every 30 seconds

def main():
    """Main production dashboard function."""
    logger.info("Starting XMRig Production Web Dashboard")

    # Start background update thread
    update_thread_handle = Thread(target=update_thread, daemon=True)
    update_thread_handle.start()

    # Initial data update
    dashboard.update_data()

    # Start Flask app
    logger.info("Dashboard available at http://localhost:23000")
    app.run(host='127.0.0.1', port=23000, debug=False)

if __name__ == "__main__":
    main()