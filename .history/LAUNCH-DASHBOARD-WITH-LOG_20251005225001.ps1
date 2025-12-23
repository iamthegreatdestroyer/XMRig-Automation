#!/usr/bin/env pwsh
# Run dashboard with full error output to a log file

$DASHBOARD_PATH = Join-Path $PSScriptRoot "dashboard"
$LOG_FILE = Join-Path $PSScriptRoot "dashboard-errors.log"

Write-Host "Launching dashboard with error logging..." -ForegroundColor Cyan
Write-Host "Log file: $LOG_FILE" -ForegroundColor Yellow
Write-Host ""

Push-Location $DASHBOARD_PATH

# Run with both stdout and stderr captured
python mining-dashboard.py 2>&1 | Tee-Object -FilePath $LOG_FILE

Pop-Location

Write-Host ""
Write-Host "Dashboard closed. Check log file for errors:" -ForegroundColor Yellow
Write-Host "  $LOG_FILE" -ForegroundColor White
Write-Host ""

if (Test-Path $LOG_FILE) {
    $logContent = Get-Content $LOG_FILE -Raw
    if ($logContent -match "Error|Exception|Traceback") {
        Write-Host "❌ ERRORS FOUND:" -ForegroundColor Red
        Write-Host $logContent
    } else {
        Write-Host "✅ No obvious errors in log" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
