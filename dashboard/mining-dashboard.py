# ============================================================================
# XMRIG MINING DASHBOARD - DESKTOP APPLICATION
# ============================================================================
# Real-time monitoring dashboard that reads actual XMRig data
# 
# Features:
# - Live hashrate, shares, and earnings from XMRig logs
# - Real-time system monitoring (CPU, temp, memory)
# - Mining statistics and profitability calculations
# - Dark cyberpunk theme
# - Auto-refreshing every 2 seconds
#
# Requirements: Python 3.11+, PyQt6, psutil
# ============================================================================

import sys
import json
import os
import re
import time
from datetime import datetime, timedelta
from pathlib import Path
from urllib.request import urlopen
from urllib.error import URLError
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QGroupBox, QGridLayout, QPushButton, QTextEdit, QProgressBar
)
from PyQt6.QtCore import QTimer, Qt, QThread, pyqtSignal
from PyQt6.QtGui import QFont, QPalette, QColor
import psutil

# ============================================================================
# CONFIGURATION
# ============================================================================

class Config:
    XMRIG_PATH = r"C:\XMRig\xmrig-6.22.0"
    XMRIG_LOG = os.path.join(XMRIG_PATH, "xmrig.log")
    XMRIG_CONFIG = os.path.join(XMRIG_PATH, "config.json")
    PROFIT_SWITCHER_STATUS = r"C:\XMRig\logs\profit-switcher-status.json"
    OPTIMIZER_LOG = r"C:\XMRig\logs\optimizer.log"
    
    # Fallback log paths to check if primary doesn't exist/isn't fresh
    XMRIG_LOG_FALLBACKS = [
        os.path.join(XMRIG_PATH, "logs", "xmr-log.txt"),
        os.path.join(XMRIG_PATH, "logs", "xmrig.log"),
    ]
    
    # Update intervals (milliseconds)
    UPDATE_INTERVAL = 2000  # 2 seconds
    LOG_LINES = 100
    
    # Prices (live-fetched from CoinGecko with 5-minute cache)
    XMR_PRICE = 322.66  # Default, updated by live price fetcher
    PRICE_CACHE_TTL = 300  # seconds

# ============================================================================
# DATA READER THREAD
# ============================================================================

class DataReaderThread(QThread):
    """Background thread to read mining data without blocking UI"""
    data_updated = pyqtSignal(dict)

    _price_cache: float = Config.XMR_PRICE
    _price_cache_time: float = 0.0

    def run(self):
        while True:
            try:
                data = self.collect_mining_data()
                self.data_updated.emit(data)
            except Exception as e:
                print(f"Error collecting data: {e}")
            self.msleep(Config.UPDATE_INTERVAL)

    def collect_mining_data(self):
        data = {
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'xmrig': self.get_xmrig_data(),
            'system': self.get_system_data(),
            'profit_switcher': self.get_profit_switcher_data(),
        }
        data['earnings'] = self.calculate_earnings(
            data['xmrig']['hashrate'],
            data['profit_switcher'].get('currentCoin', 'XMR')
        )
        return data

    def _fetch_live_xmr_price(self) -> float:
        """Fetch XMR/USD from CoinGecko with 5-minute cache."""
        now = time.time()
        if now - DataReaderThread._price_cache_time < Config.PRICE_CACHE_TTL:
            return DataReaderThread._price_cache
        try:
            url = "https://api.coingecko.com/api/v3/simple/price?ids=monero&vs_currencies=usd"
            with urlopen(url, timeout=5) as resp:
                data = json.loads(resp.read())
                price = float(data['monero']['usd'])
                DataReaderThread._price_cache = price
                DataReaderThread._price_cache_time = now
                return price
        except Exception:
            return DataReaderThread._price_cache

    def _get_xmrig_data_from_api(self) -> dict | None:
        """Try to pull data from XMRig HTTP API. Returns None if unavailable."""
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            from xmrig_api_client import get_client, XMRigAPIError
            client = get_client()
            summary = client.get_summary(use_cache=False)
            uptime_secs = summary.uptime
            hours = uptime_secs // 3600
            minutes = (uptime_secs % 3600) // 60
            return {
                'running': True,
                'hashrate': summary.hashrate_60s,
                'hashrate_10s': summary.hashrate_10s,
                'hashrate_60s': summary.hashrate_60s,
                'hashrate_15m': summary.hashrate_15m,
                'accepted': summary.shares_accepted,
                'rejected': summary.shares_rejected,
                'pool': summary.pool_url,
                'uptime': f"{hours}h {minutes}m",
                'algorithm': summary.algorithm,
                'difficulty': summary.difficulty,
                'last_share': 'N/A',
                'source': 'api',
            }
        except Exception:
            return None

    def get_xmrig_data(self):
        """HTTP API first, log-file fallback."""
        api_data = self._get_xmrig_data_from_api()
        if api_data:
            return api_data

        # Fallback: legacy log-file parsing
        xmrig_data = {
            'running': False, 'hashrate': 0.0, 'hashrate_10s': 0.0,
            'hashrate_60s': 0.0, 'hashrate_15m': 0.0, 'accepted': 0,
            'rejected': 0, 'pool': 'N/A', 'uptime': '0h 0m',
            'algorithm': 'N/A', 'difficulty': 0, 'last_share': 'N/A',
            'source': 'log',
        }
        for proc in psutil.process_iter(['name']):
            if proc.info['name'] == 'xmrig.exe':
                xmrig_data['running'] = True
                try:
                    process = psutil.Process(proc.pid)
                    uptime = datetime.now() - datetime.fromtimestamp(process.create_time())
                    h = int(uptime.total_seconds() // 3600)
                    m = int((uptime.total_seconds() % 3600) // 60)
                    xmrig_data['uptime'] = f"{h}h {m}m"
                except Exception:
                    pass
                break

        if not xmrig_data['running']:
            return xmrig_data

        log_file = None
        best_mtime = 0
        for log_path in [Config.XMRIG_LOG] + Config.XMRIG_LOG_FALLBACKS:
            if os.path.exists(log_path):
                mtime = os.path.getmtime(log_path)
                if mtime > best_mtime:
                    best_mtime = mtime
                    log_file = log_path

        if not log_file:
            return xmrig_data

        try:
            with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()[-Config.LOG_LINES:]
            for line in reversed(lines):
                if 'speed' in line and 'H/s' in line:
                    m = re.search(r'speed.*?(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+H/s', line)
                    if m:
                        xmrig_data['hashrate_10s'] = float(m.group(1))
                        xmrig_data['hashrate_60s'] = float(m.group(2))
                        xmrig_data['hashrate_15m'] = float(m.group(3)) if m.group(3) != 'n/a' else 0.0
                        xmrig_data['hashrate'] = xmrig_data['hashrate_60s']
                if 'accepted' in line:
                    m = re.search(r'accepted \((\d+)/(\d+)\)', line)
                    if m:
                        xmrig_data['accepted'] = int(m.group(1))
                        xmrig_data['rejected'] = int(m.group(2))
                    m2 = re.search(r'diff (\d+)', line)
                    if m2:
                        xmrig_data['difficulty'] = int(m2.group(1))
                    tm = re.search(r'\[([\d-]+ [\d:\.]+)\]', line)
                    if tm:
                        xmrig_data['last_share'] = tm.group(1).split('.')[0]
                if 'new job from' in line:
                    m = re.search(r'from ([^\s]+)', line)
                    if m:
                        xmrig_data['pool'] = m.group(1)
                    if 'algo' in line:
                        am = re.search(r'algo (\S+)', line)
                        if am:
                            xmrig_data['algorithm'] = am.group(1)
        except Exception as e:
            print(f"Error parsing XMRig log: {e}")

        return xmrig_data
    
    def get_system_data(self):
        """Get system resource usage"""
        system_data = {
            'cpu_percent': 0.0,
            'cpu_temp': 0.0,
            'memory_used': 0.0,
            'memory_total': 0.0,
            'memory_percent': 0.0
        }
        
        try:
            # CPU usage
            system_data['cpu_percent'] = psutil.cpu_percent(interval=0.1)
            
            # Memory
            memory = psutil.virtual_memory()
            system_data['memory_used'] = memory.used / (1024 ** 3)  # GB
            system_data['memory_total'] = memory.total / (1024 ** 3)  # GB
            system_data['memory_percent'] = memory.percent
            
            # Temperature (try multiple methods)
            try:
                temps = psutil.sensors_temperatures()
                if temps:
                    for name, entries in temps.items():
                        for entry in entries:
                            if entry.current > 0:
                                system_data['cpu_temp'] = entry.current
                                break
            except:
                # Fallback: estimate based on CPU usage
                system_data['cpu_temp'] = 50 + (system_data['cpu_percent'] * 0.3)
        
        except Exception as e:
            print(f"Error getting system data: {e}")
        
        return system_data
    
    def get_profit_switcher_data(self):
        """Read profit switcher status"""
        switcher_data = {
            'status': 'INACTIVE',
            'currentCoin': 'XMR',
            'currentCoinName': 'Monero',
            'currentProfit': 0.0,
            'lastCheck': 'N/A',
            'nextCheck': 'N/A'
        }
        
        try:
            if os.path.exists(Config.PROFIT_SWITCHER_STATUS):
                with open(Config.PROFIT_SWITCHER_STATUS, 'r') as f:
                    status = json.load(f)
                    switcher_data.update(status)
        except:
            pass
        
        return switcher_data
    
    def calculate_earnings(self, hashrate, coin='XMR'):
        """Calculate earnings based on hashrate with live coin price."""
        earnings = {
            'hourly_xmr': 0.0, 'daily_xmr': 0.0,
            'weekly_xmr': 0.0, 'monthly_xmr': 0.0,
            'daily_usd': 0.0, 'weekly_usd': 0.0, 'monthly_usd': 0.0,
            'xmr_price': Config.XMR_PRICE,
        }
        if hashrate <= 0:
            return earnings

        # Fetch live price (cached 5 min)
        live_price = self._fetch_live_xmr_price()
        Config.XMR_PRICE = live_price
        earnings['xmr_price'] = live_price

        # Physics formula: your_hash / network_hash * block_reward * blocks_per_day
        # XMR network: ~3.2 GH/s, 0.6 XMR block reward, 720 blocks/day (2-min blocks)
        network_hs = 3.2e9
        xmr_per_hash_per_day = (0.6 * 720) / network_hs

        earnings['hourly_xmr']  = (hashrate * xmr_per_hash_per_day) / 24
        earnings['daily_xmr']   = hashrate * xmr_per_hash_per_day
        earnings['weekly_xmr']  = earnings['daily_xmr'] * 7
        earnings['monthly_xmr'] = earnings['daily_xmr'] * 30

        earnings['daily_usd']   = earnings['daily_xmr']   * live_price
        earnings['weekly_usd']  = earnings['weekly_xmr']  * live_price
        earnings['monthly_usd'] = earnings['monthly_xmr'] * live_price

        return earnings

# ============================================================================
# MAIN DASHBOARD WINDOW
# ============================================================================

class MiningDashboard(QMainWindow):
    def __init__(self):
        super().__init__()
        self.init_ui()
        self.start_data_reader()
    
    def init_ui(self):
        """Initialize the user interface"""
        self.setWindowTitle("XMRig Mining Dashboard - Live Data")
        self.setGeometry(100, 100, 1400, 900)
        
        # Set dark theme
        self.set_dark_theme()
        
        # Create central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        
        # Title
        title = QLabel("⛏️ XMRIG MINING DASHBOARD")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title_font = QFont("Courier New", 24, QFont.Weight.Bold)
        title.setFont(title_font)
        title.setStyleSheet("color: #00ff41; padding: 20px;")
        main_layout.addWidget(title)
        
        # Status bar
        self.status_label = QLabel("🔴 Connecting to XMRig...")
        self.status_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.status_label.setStyleSheet("color: #ffaa00; font-size: 16px; padding: 10px;")
        main_layout.addWidget(self.status_label)
        
        # Create main content area
        content_layout = QHBoxLayout()
        
        # Left column
        left_column = QVBoxLayout()
        left_column.addWidget(self.create_mining_stats_group())
        left_column.addWidget(self.create_earnings_group())
        content_layout.addLayout(left_column, 1)
        
        # Right column
        right_column = QVBoxLayout()
        right_column.addWidget(self.create_system_stats_group())
        right_column.addWidget(self.create_pool_info_group())
        content_layout.addLayout(right_column, 1)
        
        main_layout.addLayout(content_layout)
        
        # Log viewer at bottom
        main_layout.addWidget(self.create_log_viewer())
        
        # Control buttons
        button_layout = QHBoxLayout()
        
        self.refresh_btn = QPushButton("🔄 Refresh Now")
        self.refresh_btn.clicked.connect(self.force_refresh)
        self.refresh_btn.setStyleSheet(self.button_style())
        button_layout.addWidget(self.refresh_btn)
        
        self.open_xmrig_btn = QPushButton("📂 Open XMRig Folder")
        self.open_xmrig_btn.clicked.connect(self.open_xmrig_folder)
        self.open_xmrig_btn.setStyleSheet(self.button_style())
        button_layout.addWidget(self.open_xmrig_btn)
        
        self.pool_btn = QPushButton("🌐 Open Pool Dashboard")
        self.pool_btn.clicked.connect(self.open_pool_dashboard)
        self.pool_btn.setStyleSheet(self.button_style())
        button_layout.addWidget(self.pool_btn)
        
        main_layout.addLayout(button_layout)
        
        # Footer
        footer = QLabel(f"Last Updated: Waiting for data... | Auto-refresh: Every 2 seconds")
        footer.setAlignment(Qt.AlignmentFlag.AlignCenter)
        footer.setStyleSheet("color: #888; padding: 10px;")
        self.footer_label = footer
        main_layout.addWidget(footer)
    
    def create_mining_stats_group(self):
        """Create mining statistics group"""
        group = QGroupBox("⛏️ MINING STATISTICS")
        group.setStyleSheet(self.group_style())
        layout = QGridLayout()
        
        # Hashrate
        layout.addWidget(QLabel("Current Hashrate:"), 0, 0)
        self.hashrate_label = QLabel("0.00 H/s")
        self.hashrate_label.setStyleSheet("color: #00ff41; font-size: 24px; font-weight: bold;")
        layout.addWidget(self.hashrate_label, 0, 1)
        
        # Hashrate breakdown
        layout.addWidget(QLabel("10s / 60s / 15m:"), 1, 0)
        self.hashrate_detail_label = QLabel("0.0 / 0.0 / 0.0 H/s")
        self.hashrate_detail_label.setStyleSheet("color: #00aaff;")
        layout.addWidget(self.hashrate_detail_label, 1, 1)
        
        # Shares
        layout.addWidget(QLabel("Accepted Shares:"), 2, 0)
        self.accepted_label = QLabel("0")
        self.accepted_label.setStyleSheet("color: #00ff00; font-size: 18px;")
        layout.addWidget(self.accepted_label, 2, 1)
        
        layout.addWidget(QLabel("Rejected Shares:"), 3, 0)
        self.rejected_label = QLabel("0")
        self.rejected_label.setStyleSheet("color: #ff4444;")
        layout.addWidget(self.rejected_label, 3, 1)
        
        # Success rate
        layout.addWidget(QLabel("Success Rate:"), 4, 0)
        self.success_rate_label = QLabel("0.0%")
        self.success_rate_label.setStyleSheet("color: #00ff41; font-size: 16px;")
        layout.addWidget(self.success_rate_label, 4, 1)
        
        self.success_bar = QProgressBar()
        self.success_bar.setStyleSheet(self.progress_style())
        layout.addWidget(self.success_bar, 5, 0, 1, 2)
        
        # Uptime
        layout.addWidget(QLabel("Mining Uptime:"), 6, 0)
        self.uptime_label = QLabel("0h 0m")
        self.uptime_label.setStyleSheet("color: #ffaa00;")
        layout.addWidget(self.uptime_label, 6, 1)
        
        group.setLayout(layout)
        return group
    
    def create_earnings_group(self):
        """Create earnings group"""
        group = QGroupBox("💰 ESTIMATED EARNINGS")
        group.setStyleSheet(self.group_style())
        layout = QGridLayout()
        
        layout.addWidget(QLabel("Hourly:"), 0, 0)
        self.hourly_label = QLabel("0.0000 XMR ($0.00)")
        self.hourly_label.setStyleSheet("color: #00ff41;")
        layout.addWidget(self.hourly_label, 0, 1)
        
        layout.addWidget(QLabel("Daily:"), 1, 0)
        self.daily_label = QLabel("0.0000 XMR ($0.00)")
        self.daily_label.setStyleSheet("color: #00ff41; font-size: 18px; font-weight: bold;")
        layout.addWidget(self.daily_label, 1, 1)
        
        layout.addWidget(QLabel("Weekly:"), 2, 0)
        self.weekly_label = QLabel("0.0000 XMR ($0.00)")
        self.weekly_label.setStyleSheet("color: #00aaff;")
        layout.addWidget(self.weekly_label, 2, 1)
        
        layout.addWidget(QLabel("Monthly:"), 3, 0)
        self.monthly_label = QLabel("0.0000 XMR ($0.00)")
        self.monthly_label.setStyleSheet("color: #ffaa00; font-size: 18px; font-weight: bold;")
        layout.addWidget(self.monthly_label, 3, 1)
        
        group.setLayout(layout)
        return group
    
    def create_system_stats_group(self):
        """Create system stats group"""
        group = QGroupBox("🖥️ SYSTEM RESOURCES")
        group.setStyleSheet(self.group_style())
        layout = QGridLayout()
        
        layout.addWidget(QLabel("CPU Usage:"), 0, 0)
        self.cpu_usage_label = QLabel("0.0%")
        self.cpu_usage_label.setStyleSheet("color: #00ff41; font-size: 18px;")
        layout.addWidget(self.cpu_usage_label, 0, 1)
        
        self.cpu_bar = QProgressBar()
        self.cpu_bar.setStyleSheet(self.progress_style())
        layout.addWidget(self.cpu_bar, 1, 0, 1, 2)
        
        layout.addWidget(QLabel("CPU Temperature:"), 2, 0)
        self.temp_label = QLabel("0.0°C")
        self.temp_label.setStyleSheet("color: #00ff41; font-size: 18px;")
        layout.addWidget(self.temp_label, 2, 1)
        
        layout.addWidget(QLabel("Memory Usage:"), 3, 0)
        self.memory_label = QLabel("0.0 / 0.0 GB (0%)")
        self.memory_label.setStyleSheet("color: #00aaff;")
        layout.addWidget(self.memory_label, 3, 1)
        
        self.memory_bar = QProgressBar()
        self.memory_bar.setStyleSheet(self.progress_style())
        layout.addWidget(self.memory_bar, 4, 0, 1, 2)
        
        group.setLayout(layout)
        return group
    
    def create_pool_info_group(self):
        """Create pool info group"""
        group = QGroupBox("🌐 POOL & COIN INFO")
        group.setStyleSheet(self.group_style())
        layout = QGridLayout()
        
        layout.addWidget(QLabel("Current Coin:"), 0, 0)
        self.coin_label = QLabel("Monero (XMR)")
        self.coin_label.setStyleSheet("color: #ffaa00; font-size: 16px; font-weight: bold;")
        layout.addWidget(self.coin_label, 0, 1)
        
        layout.addWidget(QLabel("Algorithm:"), 1, 0)
        self.algo_label = QLabel("N/A")
        self.algo_label.setStyleSheet("color: #00aaff;")
        layout.addWidget(self.algo_label, 1, 1)
        
        layout.addWidget(QLabel("Pool:"), 2, 0)
        self.pool_label = QLabel("N/A")
        self.pool_label.setStyleSheet("color: #00ff41;")
        layout.addWidget(self.pool_label, 2, 1)
        
        layout.addWidget(QLabel("Difficulty:"), 3, 0)
        self.diff_label = QLabel("0")
        self.diff_label.setStyleSheet("color: #888;")
        layout.addWidget(self.diff_label, 3, 1)
        
        layout.addWidget(QLabel("Last Share:"), 4, 0)
        self.last_share_label = QLabel("N/A")
        self.last_share_label.setStyleSheet("color: #888;")
        layout.addWidget(self.last_share_label, 4, 1)
        
        layout.addWidget(QLabel("Profit Switcher:"), 5, 0)
        self.switcher_status_label = QLabel("INACTIVE")
        self.switcher_status_label.setStyleSheet("color: #ff4444;")
        layout.addWidget(self.switcher_status_label, 5, 1)
        
        group.setLayout(layout)
        return group
    
    def create_log_viewer(self):
        """Create log viewer"""
        group = QGroupBox("📋 LIVE LOG (Last 20 lines)")
        group.setStyleSheet(self.group_style())
        layout = QVBoxLayout()
        
        self.log_viewer = QTextEdit()
        self.log_viewer.setReadOnly(True)
        self.log_viewer.setMaximumHeight(200)
        self.log_viewer.setStyleSheet("""
            QTextEdit {
                background-color: #000000;
                color: #00ff41;
                font-family: 'Courier New';
                font-size: 10px;
                border: 1px solid #00ff41;
            }
        """)
        layout.addWidget(self.log_viewer)
        
        group.setLayout(layout)
        return group
    
    def start_data_reader(self):
        """Start background thread to read data"""
        self.data_thread = DataReaderThread()
        self.data_thread.data_updated.connect(self.update_display)
        self.data_thread.start()
    
    def update_display(self, data):
        """Update all UI elements with new data"""
        # Update status
        if data['xmrig']['running']:
            self.status_label.setText("🟢 XMRig is MINING")
            self.status_label.setStyleSheet("color: #00ff00; font-size: 16px; padding: 10px;")
        else:
            self.status_label.setText("🔴 XMRig is OFFLINE")
            self.status_label.setStyleSheet("color: #ff0000; font-size: 16px; padding: 10px;")
        
        # Update mining stats
        self.hashrate_label.setText(f"{data['xmrig']['hashrate']:.2f} H/s")
        self.hashrate_detail_label.setText(
            f"{data['xmrig']['hashrate_10s']:.1f} / "
            f"{data['xmrig']['hashrate_60s']:.1f} / "
            f"{data['xmrig']['hashrate_15m']:.1f} H/s"
        )
        self.accepted_label.setText(str(data['xmrig']['accepted']))
        self.rejected_label.setText(str(data['xmrig']['rejected']))
        
        # Success rate
        total = data['xmrig']['accepted'] + data['xmrig']['rejected']
        if total > 0:
            success_rate = (data['xmrig']['accepted'] / total) * 100
            self.success_rate_label.setText(f"{success_rate:.1f}%")
            self.success_bar.setValue(int(success_rate))
        else:
            self.success_rate_label.setText("0.0%")
            self.success_bar.setValue(0)
        
        self.uptime_label.setText(data['xmrig']['uptime'])
        
        # Update earnings (with error handling)
        try:
            if 'earnings' in data and data['earnings']:
                e = data['earnings']
                hourly_usd = e.get('daily_usd', 0.0) / 24
                self.hourly_label.setText(f"{e.get('hourly_xmr', 0.0):.6f} XMR (${hourly_usd:.2f})")
                self.daily_label.setText(f"{e.get('daily_xmr', 0.0):.6f} XMR (${e.get('daily_usd', 0.0):.2f})")
                self.weekly_label.setText(f"{e.get('weekly_xmr', 0.0):.6f} XMR (${e.get('weekly_usd', 0.0):.2f})")
                self.monthly_label.setText(f"{e.get('monthly_xmr', 0.0):.6f} XMR (${e.get('monthly_usd', 0.0):.2f})")
            else:
                # No earnings data available
                self.hourly_label.setText("0.000000 XMR ($0.00)")
                self.daily_label.setText("0.000000 XMR ($0.00)")
                self.weekly_label.setText("0.000000 XMR ($0.00)")
                self.monthly_label.setText("0.000000 XMR ($0.00)")
        except Exception as e:
            print(f"Error updating earnings: {e}")
            self.hourly_label.setText("Error calculating")
            self.daily_label.setText("Error calculating")
            self.weekly_label.setText("Error calculating")
            self.monthly_label.setText("Error calculating")
        
        # Update system stats
        self.cpu_usage_label.setText(f"{data['system']['cpu_percent']:.1f}%")
        self.cpu_bar.setValue(int(data['system']['cpu_percent']))
        
        temp = data['system']['cpu_temp']
        self.temp_label.setText(f"{temp:.1f}°C")
        if temp > 80:
            self.temp_label.setStyleSheet("color: #ff0000; font-size: 18px;")
        elif temp > 75:
            self.temp_label.setStyleSheet("color: #ffaa00; font-size: 18px;")
        else:
            self.temp_label.setStyleSheet("color: #00ff00; font-size: 18px;")
        
        self.memory_label.setText(
            f"{data['system']['memory_used']:.1f} / "
            f"{data['system']['memory_total']:.1f} GB "
            f"({data['system']['memory_percent']:.1f}%)"
        )
        self.memory_bar.setValue(int(data['system']['memory_percent']))
        
        # Update pool info
        self.coin_label.setText(data['profit_switcher']['currentCoinName'])
        self.algo_label.setText(data['xmrig']['algorithm'])
        self.pool_label.setText(data['xmrig']['pool'])
        self.diff_label.setText(f"{data['xmrig']['difficulty']:,}")
        self.last_share_label.setText(data['xmrig']['last_share'])
        
        switcher_status = data['profit_switcher']['status']
        if switcher_status == 'ACTIVE':
            self.switcher_status_label.setText("ACTIVE ✅")
            self.switcher_status_label.setStyleSheet("color: #00ff00;")
        else:
            self.switcher_status_label.setText("INACTIVE")
            self.switcher_status_label.setStyleSheet("color: #ff4444;")
        
        # Update log viewer
        self.update_log_viewer()
        
        # Update footer
        self.footer_label.setText(
            f"Last Updated: {data['timestamp']} | "
            f"Auto-refresh: Every 2 seconds | "
            f"Hashrate: {data['xmrig']['hashrate']:.1f} H/s"
        )
    
    def update_log_viewer(self):
        """Update log viewer with latest XMRig log lines"""
        try:
            if os.path.exists(Config.XMRIG_LOG):
                with open(Config.XMRIG_LOG, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()[-20:]
                    self.log_viewer.setPlainText(''.join(lines))
                    # Scroll to bottom
                    self.log_viewer.verticalScrollBar().setValue(
                        self.log_viewer.verticalScrollBar().maximum()
                    )
        except:
            pass
    
    def force_refresh(self):
        """Force immediate refresh"""
        self.refresh_btn.setText("🔄 Refreshing...")
        QTimer.singleShot(100, lambda: self.refresh_btn.setText("🔄 Refresh Now"))
    
    def open_xmrig_folder(self):
        """Open XMRig folder in explorer"""
        os.startfile(Config.XMRIG_PATH)
    
    def open_pool_dashboard(self):
        """Open pool dashboard in browser"""
        import webbrowser
        webbrowser.open('https://pool.hashvault.pro/')
    
    # ========================================================================
    # STYLING METHODS
    # ========================================================================
    
    def set_dark_theme(self):
        """Set dark cyberpunk theme"""
        palette = QPalette()
        palette.setColor(QPalette.ColorRole.Window, QColor(10, 10, 10))
        palette.setColor(QPalette.ColorRole.WindowText, QColor(0, 255, 65))
        palette.setColor(QPalette.ColorRole.Base, QColor(20, 20, 20))
        palette.setColor(QPalette.ColorRole.AlternateBase, QColor(30, 30, 30))
        palette.setColor(QPalette.ColorRole.Text, QColor(0, 255, 65))
        palette.setColor(QPalette.ColorRole.Button, QColor(40, 40, 40))
        palette.setColor(QPalette.ColorRole.ButtonText, QColor(0, 255, 65))
        self.setPalette(palette)
        
        self.setStyleSheet("""
            QMainWindow {
                background-color: #0a0a0a;
            }
            QLabel {
                color: #00ff41;
                font-family: 'Courier New';
            }
            QGroupBox {
                font-weight: bold;
                font-size: 14px;
            }
        """)
    
    def group_style(self):
        return """
            QGroupBox {
                border: 2px solid #00ff41;
                border-radius: 5px;
                margin-top: 10px;
                padding: 15px;
                background-color: rgba(0, 255, 65, 0.05);
                color: #00ff41;
                font-weight: bold;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0 5px;
            }
        """
    
    def button_style(self):
        return """
            QPushButton {
                background-color: #1a4d2e;
                color: #00ff41;
                border: 2px solid #00ff41;
                border-radius: 5px;
                padding: 10px 20px;
                font-size: 14px;
                font-weight: bold;
                font-family: 'Courier New';
            }
            QPushButton:hover {
                background-color: #2a6d4e;
                border: 2px solid #00ff88;
            }
            QPushButton:pressed {
                background-color: #0a2d1e;
            }
        """
    
    def progress_style(self):
        return """
            QProgressBar {
                border: 2px solid #00ff41;
                border-radius: 5px;
                text-align: center;
                background-color: #000000;
                color: #00ff41;
                font-weight: bold;
            }
            QProgressBar::chunk {
                background-color: qlineargradient(
                    x1:0, y1:0, x2:1, y2:0,
                    stop:0 #00ff41, stop:1 #00aa41
                );
            }
        """

# ============================================================================
# MAIN APPLICATION
# ============================================================================

def main():
    app = QApplication(sys.argv)
    app.setApplicationName("XMRig Mining Dashboard")
    
    # Set application font
    font = QFont("Courier New", 10)
    app.setFont(font)
    
    dashboard = MiningDashboard()
    dashboard.show()
    
    sys.exit(app.exec())

if __name__ == '__main__':
    main()
