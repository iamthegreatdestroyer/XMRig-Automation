#!/usr/bin/env pwsh
# Create Desktop Shortcut for One-Click Dashboard Launch

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Creating Desktop Shortcut" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Paths
$vbsLauncher = Join-Path $PSScriptRoot "XMRig-Dashboard.vbs"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "XMRig Mining Dashboard.lnk"

# Verify launcher exists
if (-not (Test-Path $vbsLauncher)) {
    Write-Host "[ERROR] Launcher not found: $vbsLauncher" -ForegroundColor Red
    exit 1
}

# Create shortcut
Write-Host "Creating shortcut..." -ForegroundColor Yellow

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $vbsLauncher
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = "XMRig Mining Dashboard - One-Click Launcher (Auto-starts XMRig + Dashboard)"
$shortcut.IconLocation = "C:\Windows\System32\shell32.dll,44"  # Charts/graphs icon
$shortcut.Save()

Write-Host "[OK] Desktop shortcut created!" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Green
Write-Host "  SETUP COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Shortcut location:" -ForegroundColor Cyan
Write-Host "  $shortcutPath" -ForegroundColor White
Write-Host ""
Write-Host "What happens when you double-click:" -ForegroundColor Cyan
Write-Host "  1. Checks if XMRig is running" -ForegroundColor Yellow
Write-Host "  2. Starts XMRig if needed (hidden)" -ForegroundColor Yellow
Write-Host "  3. Launches Mining Dashboard" -ForegroundColor Yellow
Write-Host "  4. No console windows!" -ForegroundColor Yellow
Write-Host ""
Write-Host "TIP: You can also pin the shortcut to your taskbar!" -ForegroundColor Magenta
Write-Host ""
Write-Host "Ready to use! Check your desktop. 🚀" -ForegroundColor Green
Write-Host ""
