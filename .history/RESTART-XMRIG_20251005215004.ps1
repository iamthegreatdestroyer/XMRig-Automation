# ============================================================================
# RESTART XMRIG
# ============================================================================
# Stops and restarts XMRig to fix frozen mining
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Restarting XMRig" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Stop XMRig
Write-Host "[1/2] Stopping XMRig..." -ForegroundColor Yellow
$xmrigProcess = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
if ($xmrigProcess) {
    Write-Host "  Found XMRig process (PID: $($xmrigProcess.Id))" -ForegroundColor Gray
    Stop-Process -Name "xmrig" -Force
    Start-Sleep -Seconds 2
    Write-Host "  [OK] XMRig stopped" -ForegroundColor Green
} else {
    Write-Host "  XMRig was not running" -ForegroundColor Gray
}

# Start XMRig
Write-Host ""
Write-Host "[2/2] Starting XMRig..." -ForegroundColor Yellow
$xmrigPath = "C:\XMRig\xmrig-6.22.0"
$xmrigExe = Join-Path $xmrigPath "xmrig.exe"

if (Test-Path $xmrigExe) {
    Write-Host "  Starting XMRig in new window..." -ForegroundColor Gray
    Start-Process -FilePath $xmrigExe -WorkingDirectory $xmrigPath
    Start-Sleep -Seconds 3
    
    $newProcess = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if ($newProcess) {
        Write-Host "  [OK] XMRig started successfully (PID: $($newProcess.Id))" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] Failed to start XMRig" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [ERROR] XMRig not found at: $xmrigExe" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  XMRig Restarted!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Wait 10-15 seconds for XMRig to initialize," -ForegroundColor Yellow
Write-Host "then launch the dashboard:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  .\START-DASHBOARD.ps1" -ForegroundColor White
Write-Host ""
Write-Host "XMRig window should show:" -ForegroundColor Gray
Write-Host "  - RandomX initialization" -ForegroundColor DarkGray
Write-Host "  - Dataset ready" -ForegroundColor DarkGray
Write-Host "  - CPU threads ready" -ForegroundColor DarkGray
Write-Host "  - Speed: ~1900 H/s" -ForegroundColor DarkGray
Write-Host ""
