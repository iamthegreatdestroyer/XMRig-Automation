# ============================================================================
# MULTI-COIN PROFIT SWITCHER v2.0
# ============================================================================
# Autonomous multi-coin mining with intelligent profit optimization
#
# Features:
# - Real-time profitability analysis (XMR, RTM, VRSC)
# - Automatic coin switching based on market prices
# - Performance tracking and optimization
# - Network health monitoring
# - Comprehensive logging and reporting
# - Integration with optimizer.ps1
#
# Usage:
#   PowerShell -ExecutionPolicy Bypass -File profit-switcher-v2.ps1
#
# Author: DOPPELGANGER STUDIO
# License: MIT
# ============================================================================

#Requires -RunAsAdministrator

param(
    [int]$CheckIntervalMinutes = 60,
    [string]$XMRigPath = "C:\XMRig",
    [string]$ConfigPath = "$XMRigPath\configs",
    [double]$SwitchThresholdPercent = 15.0,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"
$LogFile = "$XMRigPath\logs\profit-switcher.log"

# ============================================================================
# CONFIGURATION
# ============================================================================

$CoinAPIs = @{
    XMR  = @{
        Name             = "Monero"
        PriceAPI         = "https://api.coingecko.com/api/v3/simple/price?ids=monero&vs_currencies=usd"
        PriceField       = "monero"
        Algorithm        = "RandomX"
        ExpectedHashrate = 1900  # H/s
        DailyReward      = 0.002      # XMR per day
        ConfigFile       = "config-xmr.json"
        Pool             = "pool.hashvault.pro:3333"
        PoolBackup       = "xmrpool.eu:3333"
    }
    RTM  = @{
        Name             = "Raptoreum"
        PriceAPI         = "https://api.coingecko.com/api/v3/simple/price?ids=raptoreum&vs_currencies=usd"
        PriceField       = "raptoreum"
        Algorithm        = "GhostRider"
        ExpectedHashrate = 3500  # H/s
        DailyReward      = 60         # RTM per day
        ConfigFile       = "config-rtm.json"
        Pool             = "rtm.suprnova.cc:6273"
        PoolBackup       = "raptoreum.na.mine.zergpool.com:3008"
    }
    VRSC = @{
        Name             = "Verus"
        PriceAPI         = "https://api.coingecko.com/api/v3/simple/price?ids=verus-coin&vs_currencies=usd"
        PriceField       = "verus-coin"
        Algorithm        = "VerusHash"
        ExpectedHashrate = 10000 # H/s
        DailyReward      = 0.8        # VRSC per day
        ConfigFile       = "config-vrsc.json"
        Pool             = "na.luckpool.net:3956"
        PoolBackup       = "verus.na.mine.zergpool.com:3300"
    }
}

$CurrentCoin = "XMR"  # Default starting coin
$SwitchHistory = @()
$PerformanceData = @{}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "DEBUG" { "Gray" }
        default { "Cyan" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    try {
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-CoinPrice {
    param([string]$CoinSymbol)
    
    $coinData = $CoinAPIs[$CoinSymbol]
    if (-not $coinData) {
        Write-Log "Unknown coin: $CoinSymbol" "ERROR"
        return 0
    }
    
    try {
        Write-Log "Fetching $($coinData.Name) price..." "DEBUG"
        $response = Invoke-RestMethod -Uri $coinData.PriceAPI -TimeoutSec 10 -ErrorAction Stop
        $price = $response.($coinData.PriceField).usd
        Write-Log "$($coinData.Name): `$$price USD" "DEBUG"
        return [double]$price
    }
    catch {
        Write-Log "Failed to fetch $($coinData.Name) price: $($_.Exception.Message)" "WARNING"
        return 0
    }
}

function Calculate-DailyProfit {
    param([string]$CoinSymbol, [double]$Price)
    
    $coinData = $CoinAPIs[$CoinSymbol]
    $dailyProfit = $Price * $coinData.DailyReward
    
    return @{
        Coin             = $CoinSymbol
        Name             = $coinData.Name
        Price            = $Price
        DailyReward      = $coinData.DailyReward
        DailyProfit      = $dailyProfit
        Algorithm        = $coinData.Algorithm
        ExpectedHashrate = $coinData.ExpectedHashrate
    }
}

function Test-PoolConnectivity {
    param([string]$PoolUrl)
    
    if ($PoolUrl -match "^([^:]+):(\d+)$") {
        $hostname = $matches[1]
        $port = [int]$matches[2]
        
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $tcpClient.BeginConnect($hostname, $port, $null, $null)
            $wait = $asyncResult.AsyncWaitHandle.WaitOne(3000, $false)
            
            if ($wait) {
                $tcpClient.EndConnect($asyncResult)
                $tcpClient.Close()
                return $true
            }
            else {
                $tcpClient.Close()
                return $false
            }
        }
        catch {
            return $false
        }
    }
    
    return $false
}

function Get-MiningProcess {
    return Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
}

function Stop-Mining {
    Write-Log "Stopping XMRig..." "INFO"
    
    $process = Get-MiningProcess
    if ($process) {
        try {
            Stop-Process -Name "xmrig" -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
            Write-Log "XMRig stopped successfully" "SUCCESS"
            return $true
        }
        catch {
            Write-Log "Failed to stop XMRig: $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
    else {
        Write-Log "XMRig is not running" "WARNING"
        return $true
    }
}

function Start-Mining {
    param([string]$CoinSymbol)
    
    $coinData = $CoinAPIs[$CoinSymbol]
    $configSource = Join-Path $ConfigPath $coinData.ConfigFile
    $configDest = Join-Path $XMRigPath "config.json"
    
    if (-not (Test-Path $configSource)) {
        Write-Log "Config file not found: $configSource" "ERROR"
        return $false
    }
    
    try {
        # Copy configuration
        Copy-Item -Path $configSource -Destination $configDest -Force -ErrorAction Stop
        Write-Log "Loaded $($coinData.Name) configuration" "SUCCESS"
        
        # Start XMRig
        $xmrigExe = Join-Path $XMRigPath "xmrig.exe"
        if (-not (Test-Path $xmrigExe)) {
            Write-Log "XMRig executable not found: $xmrigExe" "ERROR"
            return $false
        }
        
        $startScript = Join-Path $XMRigPath "start-mining.bat"
        if (Test-Path $startScript) {
            Start-Process -FilePath $startScript -WorkingDirectory $XMRigPath -WindowStyle Minimized
            Write-Log "Started mining $($coinData.Name)" "SUCCESS"
        }
        else {
            # Fallback: direct execution
            Start-Process -FilePath $xmrigExe -WorkingDirectory $XMRigPath -WindowStyle Minimized
            Write-Log "Started XMRig directly (no start script)" "WARNING"
        }
        
        Start-Sleep -Seconds 5
        return $true
    }
    catch {
        Write-Log "Failed to start mining: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Switch-ToCoin {
    param([string]$CoinSymbol, [string]$Reason)
    
    if ($DryRun) {
        Write-Log "[DRY RUN] Would switch to $($CoinAPIs[$CoinSymbol].Name): $Reason" "INFO"
        return $true
    }
    
    Write-Log "=== SWITCHING TO $($CoinAPIs[$CoinSymbol].Name) ===" "SUCCESS"
    Write-Log "Reason: $Reason" "INFO"
    
    # Stop current mining
    if (-not (Stop-Mining)) {
        Write-Log "Failed to stop mining, aborting switch" "ERROR"
        return $false
    }
    
    # Start new coin
    if (-not (Start-Mining -CoinSymbol $CoinSymbol)) {
        Write-Log "Failed to start $($CoinAPIs[$CoinSymbol].Name), reverting..." "ERROR"
        Start-Mining -CoinSymbol $CurrentCoin
        return $false
    }
    
    # Record switch
    $script:CurrentCoin = $CoinSymbol
    $script:SwitchHistory += @{
        Timestamp = Get-Date
        Coin      = $CoinSymbol
        Reason    = $Reason
    }
    
    Write-Log "Successfully switched to $($CoinAPIs[$CoinSymbol].Name)" "SUCCESS"
    return $true
}

function Get-ProfitabilityReport {
    Write-Log "`n╔════════════════════════════════════════════════════════════╗" "INFO"
    Write-Log "║          PROFITABILITY ANALYSIS REPORT                     ║" "INFO"
    Write-Log "╚════════════════════════════════════════════════════════════╝" "INFO"
    Write-Log "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" "INFO"
    
    $profits = @{}
    $bestCoin = $null
    $bestProfit = 0
    
    foreach ($coin in $CoinAPIs.Keys) {
        $price = Get-CoinPrice -CoinSymbol $coin
        
        if ($price -gt 0) {
            $profitData = Calculate-DailyProfit -CoinSymbol $coin -Price $price
            $profits[$coin] = $profitData
            
            $logLine = "  {0,-10} | " + '$' + "{1,-8:F4} | {2,6} {3}/day | " + '$' + "{4,-8:F2}/day | {5}" -f `
                $profitData.Name, `
                $profitData.Price, `
                $profitData.DailyReward, `
                $coin, `
                $profitData.DailyProfit, `
                $profitData.Algorithm
            Write-Log $logLine "INFO"
            
            if ($profitData.DailyProfit -gt $bestProfit) {
                $bestProfit = $profitData.DailyProfit
                $bestCoin = $coin
            }
        }
        else {
            Write-Log "  $($CoinAPIs[$coin].Name): Price unavailable" "WARNING"
        }
    }
    
    Write-Log "`n  Current Mining: $($CoinAPIs[$CurrentCoin].Name) ($CurrentCoin)" "INFO"
    Write-Log "  Most Profitable: $($CoinAPIs[$bestCoin].Name) ($bestCoin) - `$$($bestProfit.ToString('F2'))/day`n" "SUCCESS"
    Write-Log "════════════════════════════════════════════════════════════`n" "INFO"
    
    return @{
        Profits    = $profits
        BestCoin   = $bestCoin
        BestProfit = $bestProfit
    }
}

function Should-SwitchCoin {
    param($Report)
    
    $currentProfit = $Report.Profits[$CurrentCoin].DailyProfit
    $bestProfit = $Report.BestProfit
    $bestCoin = $Report.BestCoin
    
    if ($bestCoin -eq $CurrentCoin) {
        Write-Log "Already mining most profitable coin ($($CoinAPIs[$CurrentCoin].Name))" "SUCCESS"
        return $null
    }
    
    $profitIncrease = (($bestProfit - $currentProfit) / $currentProfit) * 100
    
    if ($profitIncrease -ge $SwitchThresholdPercent) {
        Write-Log "Profit increase: +$($profitIncrease.ToString('F1'))% (threshold: $SwitchThresholdPercent%)" "INFO"
        return $bestCoin
    }
    else {
        Write-Log "Profit increase only +$($profitIncrease.ToString('F1'))% (below threshold: $SwitchThresholdPercent%)" "INFO"
        return $null
    }
}

function Initialize-ProfitSwitcher {
    Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     🤖 MULTI-COIN PROFIT SWITCHER v2.0 🤖                 ║
║                                                           ║
║  Autonomous Profit Optimization System                    ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

    Write-Log "Profit Switcher v2.0 - Initializing..." "INFO"
    Write-Log "XMRig Path: $XMRigPath" "INFO"
    Write-Log "Config Path: $ConfigPath" "INFO"
    Write-Log "Check Interval: $CheckIntervalMinutes minutes" "INFO"
    Write-Log "Switch Threshold: $SwitchThresholdPercent%" "INFO"
    Write-Log "Dry Run: $($DryRun.IsPresent)" "INFO"
    
    # Verify directories
    if (-not (Test-Path $XMRigPath)) {
        Write-Log "XMRig path not found: $XMRigPath" "ERROR"
        return $false
    }
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Log "Creating config directory: $ConfigPath" "WARNING"
        New-Item -ItemType Directory -Path $ConfigPath -Force | Out-Null
    }
    
    # Verify configs exist
    $missingConfigs = @()
    foreach ($coin in $CoinAPIs.Keys) {
        $configFile = Join-Path $ConfigPath $CoinAPIs[$coin].ConfigFile
        if (-not (Test-Path $configFile)) {
            $missingConfigs += "$coin ($configFile)"
        }
    }
    
    if ($missingConfigs.Count -gt 0) {
        Write-Log "WARNING: Missing configuration files:" "WARNING"
        foreach ($config in $missingConfigs) {
            Write-Log "  - $config" "WARNING"
        }
        Write-Log "Run MASTER-SETUP.ps1 to generate all configs" "WARNING"
    }
    
    Write-Log "Initialization complete`n" "SUCCESS"
    return $true
}

# ============================================================================
# MAIN LOOP
# ============================================================================

function Start-ProfitSwitcher {
    if (-not (Initialize-ProfitSwitcher)) {
        Write-Log "Initialization failed, exiting..." "ERROR"
        exit 1
    }
    
    $checkCounter = 0
    
    Write-Log "Starting profit monitoring loop...`n" "SUCCESS"
    
    while ($true) {
        try {
            # Generate profitability report
            $report = Get-ProfitabilityReport
            
            # Determine if switch is needed
            $targetCoin = Should-SwitchCoin -Report $report
            
            if ($targetCoin) {
                $reason = "Profit optimization: $($CoinAPIs[$targetCoin].Name) is $SwitchThresholdPercent% more profitable"
                Switch-ToCoin -CoinSymbol $targetCoin -Reason $reason
            }
            
            # Check if miner crashed
            $process = Get-MiningProcess
            if (-not $process) {
                Write-Log "XMRig is not running! Restarting..." "ERROR"
                Start-Mining -CoinSymbol $CurrentCoin
            }
            
            # Sleep until next check
            $nextCheck = (Get-Date).AddMinutes($CheckIntervalMinutes)
            Write-Log "Next check at: $($nextCheck.ToString('HH:mm:ss'))" "INFO"
            Write-Log "═══════════════════════════════════════════════════════════`n" "INFO"
            
            Start-Sleep -Seconds ($CheckIntervalMinutes * 60)
        }
        catch {
            Write-Log "Error in main loop: $($_.Exception.Message)" "ERROR"
            Write-Log "Retrying in 5 minutes..." "WARNING"
            Start-Sleep -Seconds 300
        }
    }
}

# ============================================================================
# ENTRY POINT
# ============================================================================

Start-ProfitSwitcher
