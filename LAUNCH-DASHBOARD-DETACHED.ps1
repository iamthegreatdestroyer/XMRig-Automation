#!/usr/bin/env pwsh
# Launch dashboard in detached mode (runs in background)

$dashboardPath = Join-Path $PSScriptRoot "dashboard"
$pythonScript = Join-Path $dashboardPath "mining-dashboard.py"

Write-Host "🚀 Launching XMRig Dashboard in background..." -ForegroundColor Cyan
Write-Host ""

# Start Python process detached (no console window blocking)
$process = Start-Process -FilePath "python" `
    -ArgumentList "`"$pythonScript`"" `
    -WorkingDirectory $dashboardPath `
    -WindowStyle Hidden `
    -PassThru

Write-Host "✅ Dashboard launched (PID: $($process.Id))" -ForegroundColor Green
Write-Host ""
Write-Host "📊 The dashboard window should appear shortly!" -ForegroundColor Yellow
Write-Host ""
Write-Host "To stop the dashboard:" -ForegroundColor Cyan
Write-Host "  Stop-Process -Id $($process.Id)" -ForegroundColor White
Write-Host ""
