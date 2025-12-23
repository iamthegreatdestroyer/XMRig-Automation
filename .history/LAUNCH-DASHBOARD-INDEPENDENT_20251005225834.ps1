#!/usr/bin/env pwsh
# INDEPENDENT DASHBOARD LAUNCHER
# Launches dashboard in a completely separate process tree

$DASHBOARD_PATH = Join-Path $PSScriptRoot "dashboard"
$DASHBOARD_SCRIPT = Join-Path $DASHBOARD_PATH "mining-dashboard.py"

# Create a temporary VBScript to launch Python independently
$tempVBS = Join-Path $env:TEMP "launch-dashboard-temp.vbs"

$vbsContent = @"
Set shell = CreateObject("WScript.Shell")
shell.CurrentDirectory = "$($DASHBOARD_PATH -replace '\\', '\\')"
shell.Run "pythonw.exe mining-dashboard.py", 0, False
"@

Set-Content -Path $tempVBS -Value $vbsContent -Force

# Execute the VBS (launches Python independently)
Start-Process -FilePath "wscript.exe" -ArgumentList "`"$tempVBS`"" -WindowStyle Hidden

# Wait a moment for dashboard to start
Start-Sleep -Seconds 3

# Clean up temp file
Remove-Item $tempVBS -Force -ErrorAction SilentlyContinue

Write-Host "Dashboard launched independently!" -ForegroundColor Green
Write-Host "Check your taskbar for the dashboard window." -ForegroundColor Cyan
