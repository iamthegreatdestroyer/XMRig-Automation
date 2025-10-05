# ============================================================================
# START ALL ADVANCED FEATURES - Master Launcher
# ============================================================================
# Right-click this file and select "Run with PowerShell"
# This will start:
#   1. XMRig Miner (if not running)
#   2. Autonomous Optimizer (in background)
#   3. Multi-Coin Profit Switcher (in background)
#   4. Mining Dashboard (in browser)
# ============================================================================

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  ADVANCED FEATURES REQUIRE ADMINISTRATOR PRIVILEGES        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Relaunching with Administrator privileges..." -ForegroundColor Green
    Write-Host ""
    
    # Relaunch as Administrator
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║     XMRIG ADVANCED MINING SUITE v2.0 - FULL LAUNCH        ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# Ensure all files are copied from repository
Write-Host "📦 Preparing files..." -ForegroundColor Cyan
Write-Host ""

# Copy advanced scripts
if (-not (Test-Path "C:\XMRig\optimizer-v3.ps1") -or -not (Test-Path "C:\XMRig\profit-switcher-v2.ps1")) {
    Write-Host "  -> Copying advanced scripts..." -ForegroundColor Yellow
    Copy-Item -Path "C:\Users\sgbil\XMRig-Automation\advanced\*" -Destination "C:\XMRig\" -Force
    Write-Host "  [OK] Scripts copied" -ForegroundColor Green
}

# Copy configs
if (-not (Test-Path "C:\XMRig\configs\config-xmr.json")) {
    Write-Host "  -> Copying configuration files..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path "C:\XMRig\configs" -Force | Out-Null
    Copy-Item -Path "C:\Users\sgbil\XMRig-Automation\configs\*" -Destination "C:\XMRig\configs\" -Recurse -Force
    Write-Host "  [OK] Configs copied" -ForegroundColor Green
}

# Copy dashboard
if (-not (Test-Path "C:\XMRig\dashboard\mining-dashboard-v2.html")) {
    Write-Host "  -> Copying dashboard..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path "C:\XMRig\dashboard" -Force | Out-Null
    Copy-Item -Path "C:\Users\sgbil\XMRig-Automation\dashboard\*" -Destination "C:\XMRig\dashboard\" -Recurse -Force
    Write-Host "  [OK] Dashboard copied" -ForegroundColor Green
}

Write-Host ""
Write-Host "🚀 Starting components..." -ForegroundColor Cyan
Write-Host ""

# Step 1: Start XMRig if not running
$xmrigProcess = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
if (-not $xmrigProcess) {
    if (Test-Path "C:\XMRig\xmrig.exe") {
        Write-Host "  [1/4] Starting XMRig Miner..." -ForegroundColor Yellow
        Set-Location "C:\XMRig"
        Start-Process -FilePath "C:\XMRig\xmrig.exe" -WorkingDirectory "C:\XMRig"
        Start-Sleep -Seconds 5
        Write-Host "        ✅ XMRig started" -ForegroundColor Green
    } else {
        Write-Host "  [1/4] ❌ ERROR: XMRig not found at C:\XMRig\xmrig.exe" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
} else {
    Write-Host "  [1/4] [OK] XMRig already running (PID: $($xmrigProcess.Id))" -ForegroundColor Green
}

# Step 2: Start Optimizer in background
Write-Host "  [2/4] Starting Autonomous Optimizer..." -ForegroundColor Yellow
$optimizerJob = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"C:\XMRig\optimizer-v3.ps1`"" -PassThru -WindowStyle Minimized
Write-Host "        [OK] Optimizer started (PID: $($optimizerJob.Id))" -ForegroundColor Green

# Step 3: Start Profit Switcher in background
Write-Host "  [3/4] Starting Multi-Coin Profit Switcher..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
$switcherJob = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"C:\XMRig\profit-switcher-v2.ps1`"" -PassThru -WindowStyle Minimized
Write-Host "        [OK] Profit Switcher started (PID: $($switcherJob.Id))" -ForegroundColor Green

# Step 4: Open Dashboard
Write-Host "  [4/4] Opening Mining Dashboard..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
if (Test-Path "C:\XMRig\dashboard\mining-dashboard-v2.html") {
    Start-Process "C:\XMRig\dashboard\mining-dashboard-v2.html"
    Write-Host "        [OK] Dashboard opened in browser" -ForegroundColor Green
} else {
    Write-Host "        [!] Dashboard not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Gray
Write-Host ""
Write-Host "*** ALL SYSTEMS OPERATIONAL! ***" -ForegroundColor Green
Write-Host ""
Write-Host "  Status Summary:" -ForegroundColor Cyan
Write-Host "  • XMRig Miner: RUNNING" -ForegroundColor White
Write-Host "  • Autonomous Optimizer: RUNNING (background)" -ForegroundColor White
Write-Host "  • Profit Switcher: RUNNING (background)" -ForegroundColor White
Write-Host "  • Dashboard: OPEN (browser)" -ForegroundColor White
Write-Host ""
Write-Host "  Your mining operation is now fully autonomous!" -ForegroundColor Green
Write-Host ""
Write-Host "  Logs are located at:" -ForegroundColor Cyan
Write-Host "    C:\XMRig\logs\optimizer.log" -ForegroundColor White
Write-Host "    C:\XMRig\logs\profit-switcher.log" -ForegroundColor White
Write-Host "    C:\XMRig\logs\xmr-log.txt" -ForegroundColor White
Write-Host ""
Write-Host "  To view real-time logs:" -ForegroundColor Cyan
Write-Host "    Get-Content C:\XMRig\logs\optimizer.log -Wait" -ForegroundColor Yellow
Write-Host "    Get-Content C:\XMRig\logs\profit-switcher.log -Wait" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Press any key to exit this launcher..." -ForegroundColor Gray
Write-Host "  (Background processes will continue running)" -ForegroundColor Gray
Write-Host ""

$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Write-Host ""
Write-Host "[OK] Launcher closed. Mining continues in background." -ForegroundColor Green
Write-Host ""
