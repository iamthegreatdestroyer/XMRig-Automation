# ============================================================================
# TEST DASHBOARD LAUNCH
# ============================================================================
# Quick test to verify the dashboard can be launched
# ============================================================================

Write-Host "Testing Dashboard Configuration..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Check Python
Write-Host "[1/5] Testing Python..." -ForegroundColor Yellow
$pythonTest = python --version 2>&1
if ($pythonTest -match "Python") {
    Write-Host "  [OK] $pythonTest" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] Python not found" -ForegroundColor Red
    exit 1
}

# Test 2: Check PyQt6
Write-Host "[2/5] Testing PyQt6..." -ForegroundColor Yellow
$pyqt6Test = python -c "import PyQt6; print('OK')" 2>&1
if ($pyqt6Test -match "OK") {
    Write-Host "  [OK] PyQt6 is installed" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] PyQt6 not found" -ForegroundColor Red
    Write-Host "  Run: pip install PyQt6" -ForegroundColor Yellow
    exit 1
}

# Test 3: Check psutil
Write-Host "[3/5] Testing psutil..." -ForegroundColor Yellow
$psutilTest = python -c "import psutil; print('OK')" 2>&1
if ($psutilTest -match "OK") {
    Write-Host "  [OK] psutil is installed" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] psutil not found" -ForegroundColor Red
    Write-Host "  Run: pip install psutil" -ForegroundColor Yellow
    exit 1
}

# Test 4: Check dashboard files
Write-Host "[4/5] Testing dashboard files..." -ForegroundColor Yellow
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$dashboardPath = Join-Path $scriptPath "dashboard"
$dashboardScript = Join-Path $dashboardPath "mining-dashboard.py"
$requirementsFile = Join-Path $dashboardPath "requirements.txt"

if (Test-Path $dashboardScript) {
    Write-Host "  [OK] Dashboard script found: $dashboardScript" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] Dashboard script not found: $dashboardScript" -ForegroundColor Red
    exit 1
}

if (Test-Path $requirementsFile) {
    Write-Host "  [OK] Requirements file found: $requirementsFile" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Requirements file not found (not critical)" -ForegroundColor Yellow
}

# Test 5: Check XMRig
Write-Host "[5/5] Testing XMRig installation..." -ForegroundColor Yellow
$xmrigPath = "C:\XMRig\xmrig-6.22.0"
$xmrigExe = Join-Path $xmrigPath "xmrig.exe"
$xmrigLog = Join-Path $xmrigPath "xmrig.log"

if (Test-Path $xmrigExe) {
    Write-Host "  [OK] XMRig executable found: $xmrigExe" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] XMRig not found (dashboard will show no data)" -ForegroundColor Yellow
}

if (Test-Path $xmrigLog) {
    $logSize = (Get-Item $xmrigLog).Length
    $logModified = (Get-Item $xmrigLog).LastWriteTime
    Write-Host "  [OK] XMRig log found: $xmrigLog" -ForegroundColor Green
    Write-Host "       Size: $logSize bytes, Modified: $logModified" -ForegroundColor Gray
} else {
    Write-Host "  [INFO] XMRig log not found yet (will be created when mining starts)" -ForegroundColor Gray
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  [OK] Python installed" -ForegroundColor Green
Write-Host "  [OK] PyQt6 installed" -ForegroundColor Green
Write-Host "  [OK] psutil installed" -ForegroundColor Green
Write-Host "  [OK] Dashboard script found" -ForegroundColor Green
Write-Host ""
Write-Host "Dashboard is ready to launch!" -ForegroundColor Green
Write-Host ""
Write-Host "To start the dashboard, run:" -ForegroundColor Yellow
Write-Host "  .\START-DASHBOARD.ps1" -ForegroundColor White
Write-Host ""
