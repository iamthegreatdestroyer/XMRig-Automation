# ============================================================================
# DASHBOARD DIAGNOSTICS
# ============================================================================
# Diagnose why dashboard isn't showing live XMRig data
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Dashboard Diagnostics" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check 1: Is XMRig process running?
Write-Host "[1/6] Checking if XMRig process is running..." -ForegroundColor Yellow
$xmrigProcess = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
if ($xmrigProcess) {
    Write-Host "  [OK] XMRig is running (PID: $($xmrigProcess.Id))" -ForegroundColor Green
    $startTime = $xmrigProcess.StartTime
    $uptime = (Get-Date) - $startTime
    Write-Host "       Started: $startTime" -ForegroundColor Gray
    Write-Host "       Uptime: $($uptime.Hours)h $($uptime.Minutes)m" -ForegroundColor Gray
}
else {
    Write-Host "  [ERROR] XMRig is NOT running!" -ForegroundColor Red
    Write-Host "       Start XMRig first: cd C:\XMRig\xmrig-6.22.0; .\xmrig.exe" -ForegroundColor Yellow
}

# Check 2: Does log file exist?
Write-Host ""
Write-Host "[2/6] Checking XMRig log file..." -ForegroundColor Yellow
$logPath = "C:\XMRig\xmrig-6.22.0\xmrig.log"
if (Test-Path $logPath) {
    $logFile = Get-Item $logPath
    $logSize = [math]::Round($logFile.Length / 1MB, 2)
    $lastModified = $logFile.LastWriteTime
    $ageSeconds = ((Get-Date) - $lastModified).TotalSeconds
    
    Write-Host "  [OK] Log file exists: $logPath" -ForegroundColor Green
    Write-Host "       Size: $logSize MB" -ForegroundColor Gray
    Write-Host "       Last modified: $lastModified" -ForegroundColor Gray
    
    if ($ageSeconds -lt 10) {
        Write-Host "       Status: ACTIVELY WRITING (updated $([math]::Round($ageSeconds, 1))s ago)" -ForegroundColor Green
    }
    elseif ($ageSeconds -lt 60) {
        Write-Host "       Status: Recently updated ($([math]::Round($ageSeconds, 1))s ago)" -ForegroundColor Yellow
    }
    else {
        Write-Host "       Status: STALE (last update $([math]::Round($ageSeconds / 60, 1)) minutes ago)" -ForegroundColor Red
    }
}
else {
    Write-Host "  [ERROR] Log file NOT found: $logPath" -ForegroundColor Red
}

# Check 3: Read last lines of log
Write-Host ""
Write-Host "[3/6] Reading last 5 lines of log..." -ForegroundColor Yellow
if (Test-Path $logPath) {
    $lastLines = Get-Content $logPath -Tail 5 -ErrorAction SilentlyContinue
    if ($lastLines) {
        Write-Host "  Last log entries:" -ForegroundColor Gray
        foreach ($line in $lastLines) {
            Write-Host "    $line" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  [WARNING] Could not read log file" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  [SKIP] Log file doesn't exist" -ForegroundColor Gray
}

# Check 4: Look for hashrate in log
Write-Host ""
Write-Host "[4/6] Checking for hashrate data in log..." -ForegroundColor Yellow
if (Test-Path $logPath) {
    $recentLines = Get-Content $logPath -Tail 100 -ErrorAction SilentlyContinue
    $hashrateLines = $recentLines | Select-String -Pattern "speed.*H/s"
    
    if ($hashrateLines) {
        $lastHashrate = $hashrateLines | Select-Object -Last 1
        Write-Host "  [OK] Found hashrate data!" -ForegroundColor Green
        Write-Host "       $lastHashrate" -ForegroundColor Gray
    }
    else {
        Write-Host "  [WARNING] No hashrate data found in last 100 lines" -ForegroundColor Yellow
        Write-Host "       XMRig might be starting up or not mining" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  [SKIP] Log file doesn't exist" -ForegroundColor Gray
}

# Check 5: Look for share data
Write-Host ""
Write-Host "[5/6] Checking for share acceptance data..." -ForegroundColor Yellow
if (Test-Path $logPath) {
    $recentLines = Get-Content $logPath -Tail 100 -ErrorAction SilentlyContinue
    $shareLines = $recentLines | Select-String -Pattern "accepted"
    
    if ($shareLines) {
        $lastShare = $shareLines | Select-Object -Last 1
        Write-Host "  [OK] Found share data!" -ForegroundColor Green
        Write-Host "       $lastShare" -ForegroundColor Gray
    }
    else {
        Write-Host "  [INFO] No shares found yet (might be starting or unlucky)" -ForegroundColor Gray
    }
}
else {
    Write-Host "  [SKIP] Log file doesn't exist" -ForegroundColor Gray
}

# Check 6: Test Python can read the log
Write-Host ""
Write-Host "[6/6] Testing Python log file access..." -ForegroundColor Yellow
$pythonTest = @"
import os
log_path = 'C:/XMRig/xmrig-6.22.0/xmrig.log'
if os.path.exists(log_path):
    with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()[-5:]
        print(f'OK - Read {len(lines)} lines')
        for line in lines:
            if 'speed' in line.lower() or 'accepted' in line.lower():
                print(f'Found: {line.strip()[:80]}')
else:
    print('ERROR - Log file not found')
"@

$result = python -c $pythonTest 2>&1
Write-Host "  Python test result:" -ForegroundColor Gray
Write-Host "    $result" -ForegroundColor DarkGray

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Diagnostic Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($xmrigProcess) {
    Write-Host "  ✅ XMRig process running" -ForegroundColor Green
}
else {
    Write-Host "  ❌ XMRig NOT running" -ForegroundColor Red
}

if (Test-Path $logPath) {
    Write-Host "  ✅ Log file exists" -ForegroundColor Green
    if ($ageSeconds -lt 10) {
        Write-Host "  ✅ Log is being actively updated" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️  Log is stale (not updating)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  ❌ Log file missing" -ForegroundColor Red
}

Write-Host ""
Write-Host "Recommendations:" -ForegroundColor Yellow

if (-not $xmrigProcess) {
    Write-Host "  1. START XMRIG FIRST!" -ForegroundColor Red
    Write-Host "     cd C:\XMRig\xmrig-6.22.0" -ForegroundColor White
    Write-Host "     .\xmrig.exe" -ForegroundColor White
    Write-Host ""
}

if ($xmrigProcess -and $ageSeconds -gt 60) {
    Write-Host "  2. XMRig might be frozen - check XMRig window" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  3. After XMRig is running for 10-15 seconds, restart dashboard:" -ForegroundColor Yellow
Write-Host "     .\START-DASHBOARD.ps1" -ForegroundColor White
Write-Host ""
