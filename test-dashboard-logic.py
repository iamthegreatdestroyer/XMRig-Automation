#!/usr/bin/env python3
# Test dashboard data collection without GUI
import sys
import os
import re
from datetime import datetime
import psutil

# Add dashboard directory to path
sys.path.insert(0, r'C:\Users\sgbil\XMRig-Automation\dashboard')

print("=" * 60)
print("DASHBOARD DATA COLLECTION TEST")
print("=" * 60)
print()

# Test 1: Check if XMRig process is running
print("[1/5] Checking XMRig process...")
xmrig_running = False
for proc in psutil.process_iter(['name']):
    if proc.info['name'] == 'xmrig.exe':
        xmrig_running = True
        print(f"  ✓ XMRig process found (PID: {proc.pid})")
        try:
            process = psutil.Process(proc.pid)
            create_time = datetime.fromtimestamp(process.create_time())
            uptime = datetime.now() - create_time
            hours = int(uptime.total_seconds() // 3600)
            minutes = int((uptime.total_seconds() % 3600) // 60)
            print(f"    Started: {create_time}")
            print(f"    Uptime: {hours}h {minutes}m")
        except Exception as e:
            print(f"    Warning: Could not get process details: {e}")
        break

if not xmrig_running:
    print("  ✗ XMRig process NOT running!")
print()

# Test 2: Parse XMRig log
print("[2/5] Parsing XMRig log...")
log_path = r'C:\XMRig\xmrig-6.22.0\xmrig.log'
if os.path.exists(log_path):
    print(f"  ✓ Log file exists: {log_path}")
    
    # Get file stats
    stat = os.stat(log_path)
    size_mb = stat.st_size / (1024 * 1024)
    mod_time = datetime.fromtimestamp(stat.st_mtime)
    age_seconds = (datetime.now() - mod_time).total_seconds()
    
    print(f"    Size: {size_mb:.2f} MB")
    print(f"    Last modified: {mod_time}")
    print(f"    Age: {age_seconds:.1f} seconds")
    
    if age_seconds > 60:
        print(f"    ⚠ WARNING: Log is stale (over 1 minute old)!")
    
    # Parse log content
    try:
        with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()[-100:]
        
        print(f"    Read last {len(lines)} lines")
        
        # Look for hashrate
        hashrate_found = False
        for line in reversed(lines):
            if 'speed' in line and 'H/s' in line:
                match = re.search(r'speed.*?(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)\s+H/s', line)
                if match:
                    hashrate_10s = float(match.group(1))
                    hashrate_60s = float(match.group(2))
                    hashrate_15m = match.group(3)
                    print(f"    ✓ Found hashrate: {hashrate_60s} H/s")
                    print(f"      10s/60s/15m: {hashrate_10s} / {hashrate_60s} / {hashrate_15m}")
                    
                    # Extract timestamp
                    time_match = re.search(r'\[([\d-]+ [\d:\.]+)\]', line)
                    if time_match:
                        print(f"      Timestamp: {time_match.group(1)}")
                    hashrate_found = True
                    break
        
        if not hashrate_found:
            print("    ✗ No hashrate data found in last 100 lines!")
        
        # Look for shares
        share_found = False
        for line in reversed(lines):
            if 'accepted' in line:
                match = re.search(r'accepted \((\d+)/(\d+)\)', line)
                if match:
                    accepted = int(match.group(1))
                    rejected = int(match.group(2))
                    print(f"    ✓ Found shares: {accepted} accepted, {rejected} rejected")
                    share_found = True
                    break
        
        if not share_found:
            print("    ℹ No share data found (may not have mined any yet)")
        
    except Exception as e:
        print(f"    ✗ Error reading log: {e}")
else:
    print(f"  ✗ Log file NOT found: {log_path}")
print()

# Test 3: System stats
print("[3/5] Collecting system stats...")
try:
    cpu_percent = psutil.cpu_percent(interval=0.5)
    print(f"  ✓ CPU usage: {cpu_percent}%")
    
    mem = psutil.virtual_memory()
    mem_used_gb = mem.used / (1024**3)
    mem_total_gb = mem.total / (1024**3)
    print(f"  ✓ Memory: {mem_used_gb:.1f} / {mem_total_gb:.1f} GB ({mem.percent}%)")
    
    # Try to get temperature
    try:
        temps = psutil.sensors_temperatures()
        if temps:
            print(f"  ✓ Temperature sensors found: {list(temps.keys())}")
        else:
            print("  ℹ No temperature sensors available (will estimate)")
    except:
        print("  ℹ Temperature sensors not accessible (normal on some systems)")
        
except Exception as e:
    print(f"  ✗ Error getting system stats: {e}")
print()

# Test 4: Test earnings calculation
print("[4/5] Testing earnings calculation...")
test_hashrate = 1900.0
xmr_price = 322.66
xmr_per_hash_per_day = 0.002 / 1900

hourly_xmr = (test_hashrate * xmr_per_hash_per_day) / 24
daily_xmr = test_hashrate * xmr_per_hash_per_day
weekly_xmr = daily_xmr * 7
monthly_xmr = daily_xmr * 30

daily_usd = daily_xmr * xmr_price
monthly_usd = monthly_xmr * xmr_price

print(f"  Test hashrate: {test_hashrate} H/s")
print(f"  Daily earnings: {daily_xmr:.6f} XMR (${daily_usd:.2f})")
print(f"  Monthly earnings: {monthly_xmr:.6f} XMR (${monthly_usd:.2f})")
print()

# Test 5: Import dashboard module
print("[5/5] Testing dashboard module import...")
try:
    # This will test if the syntax is correct
    with open(r'C:\Users\sgbil\XMRig-Automation\dashboard\mining-dashboard.py', 'r') as f:
        code = f.read()
    
    # Check for syntax errors
    compile(code, 'mining-dashboard.py', 'exec')
    print("  ✓ Dashboard code compiles successfully!")
    print("  ✓ No syntax errors found")
except SyntaxError as e:
    print(f"  ✗ Syntax error in dashboard: {e}")
except Exception as e:
    print(f"  ✗ Error checking dashboard: {e}")
print()

# Summary
print("=" * 60)
print("SUMMARY")
print("=" * 60)
if xmrig_running:
    print("✓ XMRig process is running")
else:
    print("✗ XMRig process is NOT running - START IT FIRST!")

if os.path.exists(log_path) and age_seconds < 60:
    print("✓ Log file is fresh and being updated")
elif os.path.exists(log_path):
    print("⚠ Log file exists but is STALE - XMRig may be frozen")
else:
    print("✗ Log file doesn't exist")

print()
print("RECOMMENDATION:")
if not xmrig_running:
    print("  1. Start XMRig: cd C:\\XMRig\\xmrig-6.22.0; .\\xmrig.exe")
    print("  2. Wait 15 seconds for initialization")
    print("  3. Launch dashboard: .\\START-DASHBOARD.ps1")
elif age_seconds > 60:
    print("  1. XMRig is frozen - restart it: .\\RESTART-XMRIG.ps1")
    print("  2. Wait 15 seconds for initialization")
    print("  3. Launch dashboard: .\\START-DASHBOARD.ps1")
else:
    print("  Everything looks good! Dashboard should show live data.")
    print("  Launch with: .\\START-DASHBOARD.ps1")
