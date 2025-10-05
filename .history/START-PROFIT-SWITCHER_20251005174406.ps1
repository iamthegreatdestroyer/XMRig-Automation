# ============================================================================
# START PROFIT SWITCHER - Easy Launcher
# ============================================================================
# Right-click this file and select "Run with PowerShell"
# Or run from an Administrator PowerShell terminal
# ============================================================================

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  PROFIT SWITCHER REQUIRES ADMINISTRATOR PRIVILEGES            " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  The profit switcher needs admin access to:" -ForegroundColor Yellow
    Write-Host "    - Stop and restart XMRig" -ForegroundColor White
    Write-Host "    - Swap configuration files" -ForegroundColor White
    Write-Host "    - Switch between coins" -ForegroundColor White
    Write-Host ""
    Write-Host "  Relaunching with Administrator privileges..." -ForegroundColor Green
    Write-Host ""
    
    # Relaunch as Administrator
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "        MULTI-COIN PROFIT SWITCHER v2.0                        " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

# Check if XMRig is running
$xmrigProcess = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
if (-not $xmrigProcess) {
    Write-Host "  [!] WARNING: XMRig is not running!" -ForegroundColor Yellow
    Write-Host "  The profit switcher requires XMRig to be running." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Starting XMRig first..." -ForegroundColor Cyan
    
    # Try to start XMRig
    if (Test-Path "C:\XMRig\xmrig-6.22.0\xmrig.exe") {
        Set-Location "C:\XMRig\xmrig-6.22.0"
        Start-Process -FilePath "C:\XMRig\xmrig-6.22.0\xmrig.exe" -WorkingDirectory "C:\XMRig\xmrig-6.22.0"
        Write-Host "  [OK] XMRig started!" -ForegroundColor Green
        Write-Host "  Waiting 10 seconds for XMRig to initialize..." -ForegroundColor Cyan
        Start-Sleep -Seconds 10
    }
    else {
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

# Check if profit switcher exists
if (-not (Test-Path "C:\XMRig\profit-switcher-v2.ps1")) {
    Write-Host "  [X] ERROR: Profit Switcher not found at C:\XMRig\profit-switcher-v2.ps1" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Copying from repository..." -ForegroundColor Cyan
    Copy-Item -Path "C:\Users\sgbil\XMRig-Automation\advanced\profit-switcher-v2.ps1" -Destination "C:\XMRig\profit-switcher-v2.ps1" -Force
    Write-Host "  [OK] Profit Switcher copied!" -ForegroundColor Green
    Write-Host ""
}

# Check if configs exist
$configsExist = $true
if (-not (Test-Path "C:\XMRig\configs\config-xmr.json")) {
    Write-Host "  [!] WARNING: config-xmr.json not found" -ForegroundColor Yellow
    $configsExist = $false
}
if (-not (Test-Path "C:\XMRig\configs\config-rtm.json")) {
    Write-Host "  [!] WARNING: config-rtm.json not found" -ForegroundColor Yellow
    $configsExist = $false
}
if (-not (Test-Path "C:\XMRig\configs\config-vrsc.json")) {
    Write-Host "  [!] WARNING: config-vrsc.json not found" -ForegroundColor Yellow
    $configsExist = $false
}

if (-not $configsExist) {
    Write-Host ""
    Write-Host "  Copying configs from repository..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path "C:\XMRig\configs" -Force | Out-Null
    Copy-Item -Path "C:\Users\sgbil\XMRig-Automation\configs\*" -Destination "C:\XMRig\configs\" -Recurse -Force
    Write-Host "  [OK] Configs copied!" -ForegroundColor Green
    Write-Host ""
}

Write-Host "  Starting Multi-Coin Profit Switcher..." -ForegroundColor Cyan
Write-Host "  - Check interval: 60 minutes" -ForegroundColor White
Write-Host "  - Switch threshold: 15%" -ForegroundColor White
Write-Host "  - Supported coins: XMR, RTM, VRSC" -ForegroundColor White
Write-Host "  - Price API: CoinGecko" -ForegroundColor White
Write-Host ""
Write-Host "  Press Ctrl+C to stop the profit switcher" -ForegroundColor Yellow
Write-Host ""
Write-Host "================================================================" -ForegroundColor Gray
Write-Host ""

# Change to XMRig directory and start profit switcher
Set-Location "C:\XMRig"
& "C:\XMRig\profit-switcher-v2.ps1"
