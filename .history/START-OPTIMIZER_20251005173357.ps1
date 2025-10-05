# ==================================================    } else {
        Write-Host "  [X] ERROR: XMRig not found at C:\XMRig\xmrig.exe" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

Write-Host "  [OK] Running as Administrator" -ForegroundColor Green
Write-Host "  [OK] XMRig is running (PID: $($xmrigProcess.Id))" -ForegroundColor Green===============
# START OPTIMIZER - Easy Launcher
# ============================================================================
# Right-click this file and select "Run with PowerShell"
# Or run from an Administrator PowerShell terminal
# ============================================================================

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  OPTIMIZER REQUIRES ADMINISTRATOR PRIVILEGES               ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  The optimizer needs admin access to:" -ForegroundColor Yellow
    Write-Host "    • Monitor CPU temperature" -ForegroundColor White
    Write-Host "    • Modify XMRig configuration" -ForegroundColor White
    Write-Host "    • Restart mining process" -ForegroundColor White
    Write-Host ""
    Write-Host "  Relaunching with Administrator privileges..." -ForegroundColor Green
    Write-Host ""
    
    # Relaunch as Administrator
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║          XMRIG AUTONOMOUS OPTIMIZER v3.0                   ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

# Check if XMRig is running
$xmrigProcess = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
if (-not $xmrigProcess) {
    Write-Host "  [!] WARNING: XMRig is not running!" -ForegroundColor Yellow
    Write-Host "  The optimizer requires XMRig to be running." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Starting XMRig first..." -ForegroundColor Cyan
    
    # Try to start XMRig
    if (Test-Path "C:\XMRig\xmrig-6.22.0\xmrig.exe") {
        Set-Location "C:\XMRig\xmrig-6.22.0"
        Start-Process -FilePath "C:\XMRig\xmrig-6.22.0\xmrig.exe" -WorkingDirectory "C:\XMRig\xmrig-6.22.0"
        Write-Host "  [OK] XMRig started!" -ForegroundColor Green
        Write-Host "  Waiting 10 seconds for XMRig to initialize..." -ForegroundColor Cyan
        Start-Sleep -Seconds 10
    } else {
        Write-Host "  [X] ERROR: XMRig not found at C:\XMRig\xmrig-6.22.0\xmrig.exe" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

Write-Host "  [OK] Running as Administrator" -ForegroundColor Green
Write-Host "  [OK] XMRig is running (PID: $($xmrigProcess.Id))" -ForegroundColor Green
Write-Host ""

# Check if optimizer exists
if (-not (Test-Path "C:\XMRig\optimizer-v3.ps1")) {
    Write-Host "  [X] ERROR: Optimizer not found at C:\XMRig\optimizer-v3.ps1" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Copying from repository..." -ForegroundColor Cyan
    Copy-Item -Path "C:\Users\sgbil\XMRig-Automation\advanced\optimizer-v3.ps1" -Destination "C:\XMRig\optimizer-v3.ps1" -Force
    Write-Host "  [OK] Optimizer copied!" -ForegroundColor Green
    Write-Host ""
}

Write-Host "  Starting Autonomous Optimizer..." -ForegroundColor Cyan
Write-Host "  • Check interval: 30 minutes" -ForegroundColor White
Write-Host "  • Temperature monitoring: ENABLED" -ForegroundColor White
Write-Host "  • Performance tracking: ENABLED" -ForegroundColor White
Write-Host "  • Auto-restart: ENABLED" -ForegroundColor White
Write-Host ""
Write-Host "  Press Ctrl+C to stop the optimizer" -ForegroundColor Yellow
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Gray
Write-Host ""

# Change to XMRig directory and start optimizer
Set-Location "C:\XMRig"
& "C:\XMRig\optimizer-v3.ps1"
