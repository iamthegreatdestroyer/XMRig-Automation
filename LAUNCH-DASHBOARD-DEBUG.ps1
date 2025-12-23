#!/usr/bin/env pwsh
# DEBUG LAUNCHER - Shows errors if dashboard fails
# Use this to diagnose issues

$ErrorActionPreference = "Continue"

Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   XMRig Dashboard - Debug Launcher           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Configuration
$XMRIG_PATH = "C:\XMRig\xmrig-6.22.0"
$XMRIG_EXE = Join-Path $XMRIG_PATH "xmrig.exe"
$DASHBOARD_PATH = Join-Path $PSScriptRoot "dashboard"
$DASHBOARD_SCRIPT = Join-Path $DASHBOARD_PATH "mining-dashboard.py"

Write-Host "[1/5] Checking paths..." -ForegroundColor Yellow

# Check XMRig
if (Test-Path $XMRIG_EXE) {
    Write-Host "  ✅ XMRig found: $XMRIG_EXE" -ForegroundColor Green
}
else {
    Write-Host "  ❌ XMRig NOT found: $XMRIG_EXE" -ForegroundColor Red
}

# Check Dashboard script
if (Test-Path $DASHBOARD_SCRIPT) {
    Write-Host "  ✅ Dashboard script found: $DASHBOARD_SCRIPT" -ForegroundColor Green
}
else {
    Write-Host "  ❌ Dashboard script NOT found: $DASHBOARD_SCRIPT" -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host ""
Write-Host "[2/5] Checking Python..." -ForegroundColor Yellow

# Check Python
$pythonVersion = python --version 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ Python found: $pythonVersion" -ForegroundColor Green
}
else {
    Write-Host "  ❌ Python NOT found!" -ForegroundColor Red
    Write-Host "  Install Python from: https://python.org" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host ""
Write-Host "[3/5] Checking Python packages..." -ForegroundColor Yellow

# Check PyQt6
$pyqt6Check = python -c "import PyQt6; print('OK')" 2>&1
if ($pyqt6Check -eq "OK") {
    Write-Host "  ✅ PyQt6 installed" -ForegroundColor Green
}
else {
    Write-Host "  ❌ PyQt6 NOT installed" -ForegroundColor Red
    Write-Host "  Run: .\START-DASHBOARD.ps1" -ForegroundColor Yellow
}

# Check psutil
$psutilCheck = python -c "import psutil; print('OK')" 2>&1
if ($psutilCheck -eq "OK") {
    Write-Host "  ✅ psutil installed" -ForegroundColor Green
}
else {
    Write-Host "  ❌ psutil NOT installed" -ForegroundColor Red
    Write-Host "  Run: .\START-DASHBOARD.ps1" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[4/5] Checking XMRig status..." -ForegroundColor Yellow

$xmrigProc = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
if ($xmrigProc) {
    Write-Host "  ✅ XMRig is running (PID: $($xmrigProc.Id))" -ForegroundColor Green
}
else {
    Write-Host "  ⚠️  XMRig is NOT running" -ForegroundColor Yellow
    Write-Host "  Starting XMRig..." -ForegroundColor Cyan
    
    if (Test-Path $XMRIG_EXE) {
        Start-Process -FilePath $XMRIG_EXE -WorkingDirectory $XMRIG_PATH -WindowStyle Hidden
        Start-Sleep -Seconds 3
        
        $xmrigProc = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
        if ($xmrigProc) {
            Write-Host "  ✅ XMRig started successfully!" -ForegroundColor Green
        }
        else {
            Write-Host "  ❌ Failed to start XMRig" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "[5/5] Launching dashboard..." -ForegroundColor Yellow
Write-Host ""
Write-Host "Opening dashboard window..." -ForegroundColor Cyan
Write-Host "If you see errors below, copy them and report the issue." -ForegroundColor Magenta
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

# Launch dashboard with VISIBLE console (python, not pythonw)
# This way we can see any error messages
Push-Location $DASHBOARD_PATH
python mining-dashboard.py
$exitCode = $LASTEXITCODE
Pop-Location

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""

if ($exitCode -eq 0) {
    Write-Host "✅ Dashboard closed normally" -ForegroundColor Green
}
else {
    Write-Host "❌ Dashboard exited with error code: $exitCode" -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
