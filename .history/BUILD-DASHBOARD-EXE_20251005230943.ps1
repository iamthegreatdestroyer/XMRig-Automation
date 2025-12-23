#!/usr/bin/env pwsh
# Build standalone executable for XMRig Mining Dashboard
# This creates a single .exe file that includes Python + all dependencies

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  XMRig Dashboard - Executable Builder" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check Python
Write-Host "[1/5] Checking Python installation..." -ForegroundColor Yellow
$pythonVersion = python --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Python not found!" -ForegroundColor Red
    Write-Host "  Please install Python 3.11+ from python.org" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "  [OK] Found: $pythonVersion" -ForegroundColor Green

# Upgrade pip first
Write-Host "  [INFO] Upgrading pip..." -ForegroundColor Cyan
python -m pip install --upgrade pip --quiet 2>&1 | Out-Null
Write-Host ""

# Install PyInstaller
Write-Host "[2/5] Installing PyInstaller..." -ForegroundColor Yellow
Write-Host "  This may take a minute..." -ForegroundColor Cyan

# Disable SSL verification temporarily if needed
$env:PYTHONWARNINGS = "ignore:Unverified HTTPS request"

$pipOutput = python -m pip install --upgrade pyinstaller 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] PyInstaller ready" -ForegroundColor Green
}
else {
    Write-Host "  [ERROR] Failed to install PyInstaller" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error details:" -ForegroundColor Yellow
    Write-Host $pipOutput
    Write-Host ""
    Write-Host "Trying alternative installation method..." -ForegroundColor Cyan
    
    # Try without upgrade flag
    $pipOutput2 = python -m pip install pyinstaller 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] PyInstaller installed via alternative method" -ForegroundColor Green
    }
    else {
        Write-Host "  [ERROR] Both installation methods failed" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please try manually:" -ForegroundColor Yellow
        Write-Host "  python -m pip install --upgrade pip" -ForegroundColor White
        Write-Host "  python -m pip install pyinstaller" -ForegroundColor White
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
}
Write-Host ""

# Ensure all dependencies are installed
Write-Host "[3/5] Installing dashboard dependencies..." -ForegroundColor Yellow
$requirementsFile = Join-Path $PSScriptRoot "dashboard\requirements.txt"
python -m pip install -r $requirementsFile --quiet 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] All dependencies installed" -ForegroundColor Green
}
else {
    Write-Host "  [WARNING] Some packages may have failed" -ForegroundColor Yellow
}
Write-Host ""

# Build executable
Write-Host "[4/5] Building standalone executable..." -ForegroundColor Yellow
Write-Host "  This may take 2-3 minutes..." -ForegroundColor Cyan

$dashboardPath = Join-Path $PSScriptRoot "dashboard"
$scriptFile = Join-Path $dashboardPath "mining-dashboard.py"
$distPath = Join-Path $PSScriptRoot "dist"
$iconPath = Join-Path $dashboardPath "icon.ico"

# Create icon if it doesn't exist (optional)
if (-not (Test-Path $iconPath)) {
    Write-Host "  [INFO] No icon file found, building without icon" -ForegroundColor Yellow
    $iconArg = ""
}
else {
    $iconArg = "--icon=`"$iconPath`""
}

# PyInstaller command
Push-Location $dashboardPath
$buildCommand = @"
pyinstaller ``
    --onefile ``
    --windowed ``
    --name "XMRig-Dashboard" ``
    --distpath "$distPath" ``
    --add-data "requirements.txt;." ``
    --hidden-import PyQt6.QtCore ``
    --hidden-import PyQt6.QtGui ``
    --hidden-import PyQt6.QtWidgets ``
    --hidden-import psutil ``
    --clean ``
    $iconArg ``
    mining-dashboard.py
"@

Invoke-Expression $buildCommand 2>&1 | Out-Null

Pop-Location

if (Test-Path (Join-Path $distPath "XMRig-Dashboard.exe")) {
    Write-Host "  [OK] Executable built successfully!" -ForegroundColor Green
}
else {
    Write-Host "  [ERROR] Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Create desktop shortcut
Write-Host "[5/5] Creating desktop shortcut..." -ForegroundColor Yellow

$exePath = Join-Path $distPath "XMRig-Dashboard.exe"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "XMRig Mining Dashboard.lnk"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $exePath
$shortcut.WorkingDirectory = $distPath
$shortcut.Description = "XMRig Mining Dashboard - One-Click Monitoring"
$shortcut.Save()

Write-Host "  [OK] Desktop shortcut created!" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Green
Write-Host "  BUILD COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Executable location:" -ForegroundColor Cyan
Write-Host "  $exePath" -ForegroundColor White
Write-Host ""
Write-Host "Desktop shortcut:" -ForegroundColor Cyan
Write-Host "  $shortcutPath" -ForegroundColor White
Write-Host ""
Write-Host "File size:" -ForegroundColor Cyan
$exeSize = (Get-Item $exePath).Length / 1MB
Write-Host "  $([math]::Round($exeSize, 2)) MB" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  HOW TO USE:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Double-click 'XMRig Mining Dashboard' on your desktop" -ForegroundColor Yellow
Write-Host "2. Dashboard will launch automatically" -ForegroundColor Yellow
Write-Host "3. No installation or setup required!" -ForegroundColor Yellow
Write-Host ""
Write-Host "NOTE: XMRig must be running for the dashboard to show data" -ForegroundColor Magenta
Write-Host ""
