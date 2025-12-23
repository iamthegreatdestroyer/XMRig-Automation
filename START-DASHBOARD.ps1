# ============================================================================
# INSTALL AND RUN XMRIG MINING DASHBOARD
# ============================================================================
# This script installs Python dependencies and launches the dashboard
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  XMRig Mining Dashboard - Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Python is installed
Write-Host "[1/4] Checking Python installation..." -ForegroundColor Yellow
try {
    $pythonVersion = python --version 2>&1
    Write-Host "  [OK] Found: $pythonVersion" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Python not found!" -ForegroundColor Red
    Write-Host "  Please install Python 3.11+ from https://www.python.org/downloads/" -ForegroundColor Red
    Write-Host "  Make sure to check 'Add Python to PATH' during installation!" -ForegroundColor Yellow
    pause
    exit 1
}

# Check Python version
$versionMatch = $pythonVersion -match '(\d+)\.(\d+)'
if ($versionMatch) {
    $majorVersion = [int]$matches[1]
    $minorVersion = [int]$matches[2]
    
    if ($majorVersion -lt 3 -or ($majorVersion -eq 3 -and $minorVersion -lt 11)) {
        Write-Host "  [WARNING] Python 3.11+ recommended (you have $majorVersion.$minorVersion)" -ForegroundColor Yellow
        Write-Host "  Dashboard may still work, but consider upgrading." -ForegroundColor Yellow
    }
}

# Install pip packages
Write-Host ""
Write-Host "[2/4] Installing Python packages..." -ForegroundColor Yellow
Write-Host "  This may take a few minutes on first run..." -ForegroundColor Gray

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$dashboardPath = Join-Path $scriptPath "dashboard"
$requirementsFile = Join-Path $dashboardPath "requirements.txt"

if (-not (Test-Path $requirementsFile)) {
    Write-Host "  [WARNING] requirements.txt not found at: $requirementsFile" -ForegroundColor Yellow
    Write-Host "  Installing packages manually..." -ForegroundColor Yellow
}

# Temporarily fix PostgreSQL SSL certificate issue
$oldSSLCert = $env:SSL_CERT_FILE
$env:SSL_CERT_FILE = $null

try {
    if (Test-Path $requirementsFile) {
        $pipOutput = python -m pip install --upgrade pip 2>&1
        $installOutput = python -m pip install -r $requirementsFile 2>&1
    }
    else {
        $pipOutput = python -m pip install --upgrade pip 2>&1
        $installOutput = python -m pip install PyQt6 psutil 2>&1
    }
    
    # Check if packages are actually installed
    $pyqt6Check = python -c "import PyQt6; print('OK')" 2>&1
    $psutilCheck = python -c "import psutil; print('OK')" 2>&1
    
    if ($pyqt6Check -match "OK" -and $psutilCheck -match "OK") {
        Write-Host "  [OK] All packages installed successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "  [WARNING] Package installation completed with warnings" -ForegroundColor Yellow
        Write-Host "  Attempting to continue..." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  [ERROR] Failed to install packages: $_" -ForegroundColor Red
    Write-Host "  Try running manually: pip install PyQt6 psutil" -ForegroundColor Yellow
    pause
    exit 1
}
finally {
    # Restore original SSL certificate setting
    $env:SSL_CERT_FILE = $oldSSLCert
}

# Verify XMRig paths
Write-Host ""
Write-Host "[3/4] Verifying XMRig installation..." -ForegroundColor Yellow

$xmrigPath = "C:\XMRig\xmrig-6.22.0"
$xmrigExe = Join-Path $xmrigPath "xmrig.exe"
$xmrigLog = Join-Path $xmrigPath "xmrig.log"

if (Test-Path $xmrigExe) {
    Write-Host "  [OK] XMRig found at: $xmrigPath" -ForegroundColor Green
}
else {
    Write-Host "  [WARNING] XMRig not found at expected location" -ForegroundColor Yellow
    Write-Host "  Expected: $xmrigExe" -ForegroundColor Gray
    Write-Host "  Dashboard will still launch, but won't show data until XMRig is running" -ForegroundColor Yellow
}

if (Test-Path $xmrigLog) {
    Write-Host "  [OK] XMRig log file found" -ForegroundColor Green
}
else {
    Write-Host "  [INFO] XMRig log not found yet (will be created when mining starts)" -ForegroundColor Gray
}

# Launch dashboard
Write-Host ""
Write-Host "[4/4] Launching Mining Dashboard..." -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Dashboard Features:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  [OK] Real-time hashrate monitoring" -ForegroundColor Green
Write-Host "  [OK] Live share acceptance tracking" -ForegroundColor Green
Write-Host "  [OK] System resource monitoring" -ForegroundColor Green
Write-Host "  [OK] Earnings calculator" -ForegroundColor Green
Write-Host "  [OK] Auto-refresh every 2 seconds" -ForegroundColor Green
Write-Host "  [OK] Live log viewer" -ForegroundColor Green
Write-Host ""
Write-Host "The dashboard window will open in a few seconds..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C in this window to stop the dashboard" -ForegroundColor Gray
Write-Host ""

Start-Sleep -Seconds 2

# Launch Python dashboard
$dashboardScript = Join-Path $dashboardPath "mining-dashboard.py"

try {
    python $dashboardScript
}
catch {
    Write-Host ""
    Write-Host "[ERROR] Failed to launch dashboard: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Make sure Python is installed correctly" -ForegroundColor Gray
    Write-Host "2. Try running manually: python $dashboardScript" -ForegroundColor Gray
    Write-Host "3. Check that PyQt6 is installed: pip list | findstr PyQt6" -ForegroundColor Gray
    Write-Host ""
    pause
    exit 1
}

Write-Host ""
Write-Host "Dashboard closed." -ForegroundColor Yellow
