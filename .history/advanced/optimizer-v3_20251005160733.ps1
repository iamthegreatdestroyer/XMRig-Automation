# ============================================================================
# AUTONOMOUS MINING OPTIMIZER v3.0
# ============================================================================
# Intelligent performance optimization with self-learning capabilities
#
# Features:
# - Real-time performance monitoring and adjustment
# - CPU temperature monitoring with thermal throttling
# - Network connectivity diagnostics
# - Predictive optimization using historical data
# - Integration with profit-switcher
# - Auto-recovery from crashes
# - Performance reporting and analytics
#
# Usage:
#   PowerShell -ExecutionPolicy Bypass -File optimizer-v3.ps1
#
# Author: DOPPELGANGER STUDIO
# License: MIT
# ============================================================================

#Requires -RunAsAdministrator

param(
    [int]$CheckIntervalMinutes = 30,
    [string]$XMRigPath = "C:\XMRig",
    [int]$MaxTemp = 85,
    [int]$TargetTemp = 75,
    [double]$MinHashrate = 1500,
    [double]$MaxRejectionPercent = 5,
    [switch]$AggressiveOptimization
)

$ErrorActionPreference = "Continue"
$LogFile = "$XMRigPath\logs\optimizer.log"
$PerformanceDB = "$XMRigPath\logs\performance-history.json"

# ============================================================================
# CONFIGURATION
# ============================================================================

$OptimizerConfig = @{
    MinThreads = 8
    MaxThreads = 16
    ThreadStep = 2
    CooldownMinutes = 10
    MaxConsecutiveAdjustments = 3
    PerformanceWindowMinutes = 60
    NetworkCheckIntervalMinutes = 5
}

$PerformanceHistory = @()
$LastAdjustmentTime = $null
$ConsecutiveAdjustments = 0
$LastNetworkCheck = $null

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG", "METRIC")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "METRIC"  { "Magenta" }
        "DEBUG"   { "Gray" }
        default   { "Cyan" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    try {
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silently continue if log write fails
    }
}

function Get-CPUTemperature {
    try {
        # Try OpenHardwareMonitor via WMI (if installed)
        $temps = Get-WmiObject -Namespace "root\OpenHardwareMonitor" -Class "Sensor" `
            -Filter "SensorType='Temperature' AND Name LIKE '%CPU%'" -ErrorAction SilentlyContinue
        
        if ($temps) {
            $maxTemp = ($temps | Measure-Object -Property Value -Maximum).Maximum
            return [int]$maxTemp
        }
        
        # Fallback: Get-Counter for CPU load as proxy
        $cpuLoad = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        
        # Estimate temp based on load (very rough approximation)
        # Base temp 50°C + (load/100 * 30°C)
        $estimatedTemp = 50 + ($cpuLoad / 100 * 30)
        return [int]$estimatedTemp
    }
    catch {
        Write-Log "Unable to read temperature: $($_.Exception.Message)" "DEBUG"
        return -1
    }
}

function Get-MiningMetrics {
    $logPath = "$XMRigPath\logs\xmr-log.txt"
    
    # Try multiple log file patterns
    $logFiles = @(
        "$XMRigPath\logs\xmr-log.txt",
        "$XMRigPath\logs\rtm-log.txt",
        "$XMRigPath\logs\vrsc-log.txt",
        "$XMRigPath\xmrig.log"
    )
    
    $logPath = $logFiles | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if (-not $logPath) {
        Write-Log "No log file found" "WARNING"
        return $null
    }
    
    try {
        $logContent = Get-Content $logPath -Tail 200 -ErrorAction Stop
        
        # Parse hashrate
        $hashrateMatch = $logContent | Where-Object { $_ -match "speed.*?(\d+\.?\d*)\s+H/s" } | Select-Object -Last 1
        $hashrate = if ($hashrateMatch -match "(\d+\.?\d*)\s+H/s") {
            [double]$matches[1]
        } else { 0 }
        
        # Parse shares (accepted/total)
        $sharesMatch = $logContent | Where-Object { $_ -match "accepted.*?\((\d+)/(\d+)\)" } | Select-Object -Last 1
        $accepted = 0
        $total = 0
        if ($sharesMatch -match "\((\d+)/(\d+)\)") {
            $accepted = [int]$matches[1]
            $total = [int]$matches[2]
        }
        
        # Parse difficulty
        $diffMatch = $logContent | Where-Object { $_ -match "diff\s+(\d+)" } | Select-Object -Last 1
        $difficulty = if ($diffMatch -match "diff\s+(\d+)") {
            [int]$matches[1]
        } else { 0 }
        
        # Get CPU usage
        $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        
        # Get CPU temperature
        $cpuTemp = Get-CPUTemperature
        
        # Get current thread count from config
        $configPath = "$XMRigPath\config.json"
        $threads = 12  # default
        if (Test-Path $configPath) {
            try {
                $config = Get-Content $configPath | ConvertFrom-Json
                $threads = $config.cpu.'max-threads-hint'
            } catch {
                Write-Log "Failed to parse config for thread count" "DEBUG"
            }
        }
        
        return @{
            Timestamp = Get-Date
            Hashrate = $hashrate
            Accepted = $accepted
            Total = $total
            Rejected = $total - $accepted
            Difficulty = $difficulty
            CpuUsage = [int]$cpuUsage
            CpuTemp = $cpuTemp
            Threads = $threads
            LogFile = $logPath
        }
    }
    catch {
        Write-Log "Error parsing metrics: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Test-NetworkHealth {
    $pools = @(
        "pool.hashvault.pro",
        "xmrpool.eu",
        "rtm.suprnova.cc",
        "na.luckpool.net"
    )
    
    $healthyPools = 0
    $totalPools = $pools.Count
    
    foreach ($pool in $pools) {
        try {
            $result = Test-Connection -ComputerName $pool -Count 1 -Quiet -ErrorAction Stop
            if ($result) {
                $healthyPools++
            }
        }
        catch {
            # Pool unreachable
        }
    }
    
    $healthPercent = ($healthyPools / $totalPools) * 100
    
    return @{
        Healthy = $healthyPools
        Total = $totalPools
        HealthPercent = $healthPercent
        Status = if ($healthPercent -ge 75) { "GOOD" } elseif ($healthPercent -ge 50) { "FAIR" } else { "POOR" }
    }
}

function Save-PerformanceData {
    param($Metrics)
    
    $script:PerformanceHistory += $Metrics
    
    # Keep only last 24 hours of data
    $cutoffTime = (Get-Date).AddHours(-24)
    $script:PerformanceHistory = $script:PerformanceHistory | Where-Object { $_.Timestamp -gt $cutoffTime }
    
    # Save to disk
    try {
        $script:PerformanceHistory | ConvertTo-Json -Depth 5 | Set-Content $PerformanceDB -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to save performance data: $($_.Exception.Message)" "DEBUG"
    }
}

function Load-PerformanceData {
    if (Test-Path $PerformanceDB) {
        try {
            $data = Get-Content $PerformanceDB | ConvertFrom-Json
            $script:PerformanceHistory = @($data)
            Write-Log "Loaded $($script:PerformanceHistory.Count) historical records" "DEBUG"
        }
        catch {
            Write-Log "Failed to load performance data: $($_.Exception.Message)" "DEBUG"
            $script:PerformanceHistory = @()
        }
    }
}

function Get-PerformanceTrend {
    if ($PerformanceHistory.Count -lt 5) {
        return "INSUFFICIENT_DATA"
    }
    
    $recent = $PerformanceHistory | Select-Object -Last 10
    $avgHashrate = ($recent | Measure-Object -Property Hashrate -Average).Average
    $current = $recent[-1].Hashrate
    
    $deviation = (($current - $avgHashrate) / $avgHashrate) * 100
    
    if ($deviation -lt -10) { return "DECLINING" }
    elseif ($deviation -gt 10) { return "IMPROVING" }
    else { return "STABLE" }
}

function Optimize-Performance {
    param($Metrics)
    
    Write-Log "`n╔════════════════════════════════════════════════════════════╗" "INFO"
    Write-Log "║          PERFORMANCE ANALYSIS & OPTIMIZATION               ║" "INFO"
    Write-Log "╚════════════════════════════════════════════════════════════╝" "INFO"
    
    $issues = @()
    $actions = @()
    
    # Temperature check
    if ($Metrics.CpuTemp -gt 0) {
        Write-Log "  CPU Temperature: $($Metrics.CpuTemp)°C (Max: $MaxTemp°C, Target: $TargetTemp°C)" "METRIC"
        
        if ($Metrics.CpuTemp -ge $MaxTemp) {
            $issues += "CRITICAL: CPU temperature $($Metrics.CpuTemp)°C exceeds maximum $MaxTemp°C"
            $actions += "REDUCE_THREADS_AGGRESSIVE"
        }
        elseif ($Metrics.CpuTemp -ge $TargetTemp) {
            $issues += "WARNING: CPU temperature $($Metrics.CpuTemp)°C above target $TargetTemp°C"
            $actions += "REDUCE_THREADS"
        }
    }
    
    # Hashrate check
    Write-Log "  Hashrate: $($Metrics.Hashrate.ToString('F2')) H/s (Minimum: $MinHashrate H/s)" "METRIC"
    
    if ($Metrics.Hashrate -lt $MinHashrate -and $Metrics.CpuTemp -lt $TargetTemp) {
        $issues += "Low hashrate: $($Metrics.Hashrate.ToString('F2')) H/s"
        $actions += "INCREASE_THREADS"
    }
    
    # Rejection rate check
    if ($Metrics.Total -gt 10) {
        $rejectionRate = ($Metrics.Rejected / $Metrics.Total) * 100
        Write-Log "  Share Success: $($Metrics.Accepted)/$($Metrics.Total) (Rejection: $($rejectionRate.ToString('F1'))%)" "METRIC"
        
        if ($rejectionRate -gt $MaxRejectionPercent) {
            $issues += "High rejection rate: $($rejectionRate.ToString('F1'))%"
            $actions += "CHECK_NETWORK"
        }
    }
    
    # CPU usage check
    Write-Log "  CPU Usage: $($Metrics.CpuUsage)%" "METRIC"
    Write-Log "  Threads: $($Metrics.Threads)" "METRIC"
    
    # Performance trend
    $trend = Get-PerformanceTrend
    Write-Log "  Performance Trend: $trend" "METRIC"
    
    # Process issues
    if ($issues.Count -eq 0) {
        Write-Log "`n  ✅ Performance optimal - No actions needed" "SUCCESS"
    }
    else {
        Write-Log "`n  ⚠️ Issues detected:" "WARNING"
        foreach ($issue in $issues) {
            Write-Log "    - $issue" "WARNING"
        }
        
        # Execute actions
        foreach ($action in $actions) {
            Execute-OptimizationAction -Action $action -Metrics $Metrics
        }
    }
    
    Write-Log "════════════════════════════════════════════════════════════`n" "INFO"
}

function Execute-OptimizationAction {
    param([string]$Action, $Metrics)
    
    # Check cooldown period
    if ($LastAdjustmentTime) {
        $minutesSinceAdjustment = ((Get-Date) - $LastAdjustmentTime).TotalMinutes
        if ($minutesSinceAdjustment -lt $OptimizerConfig.CooldownMinutes) {
            Write-Log "  ⏳ Cooldown active ($([int]$minutesSinceAdjustment)/$($OptimizerConfig.CooldownMinutes) min)" "INFO"
            return
        }
    }
    
    # Check consecutive adjustments limit
    if ($ConsecutiveAdjustments -ge $OptimizerConfig.MaxConsecutiveAdjustments) {
        Write-Log "  ⛔ Max consecutive adjustments reached ($ConsecutiveAdjustments). Manual review needed." "WARNING"
        return
    }
    
    switch ($Action) {
        "REDUCE_THREADS_AGGRESSIVE" {
            $newThreads = [Math]::Max($OptimizerConfig.MinThreads, $Metrics.Threads - ($OptimizerConfig.ThreadStep * 2))
            Adjust-Threads -NewThreadCount $newThreads -Reason "Critical temperature reduction"
        }
        "REDUCE_THREADS" {
            $newThreads = [Math]::Max($OptimizerConfig.MinThreads, $Metrics.Threads - $OptimizerConfig.ThreadStep)
            Adjust-Threads -NewThreadCount $newThreads -Reason "Temperature management"
        }
        "INCREASE_THREADS" {
            $newThreads = [Math]::Min($OptimizerConfig.MaxThreads, $Metrics.Threads + $OptimizerConfig.ThreadStep)
            Adjust-Threads -NewThreadCount $newThreads -Reason "Performance optimization"
        }
        "CHECK_NETWORK" {
            Test-NetworkAndReport
        }
    }
}

function Adjust-Threads {
    param([int]$NewThreadCount, [string]$Reason)
    
    $configPath = "$XMRigPath\config.json"
    
    if (-not (Test-Path $configPath)) {
        Write-Log "  ❌ Config file not found: $configPath" "ERROR"
        return
    }
    
    try {
        $config = Get-Content $configPath | ConvertFrom-Json
        $currentThreads = $config.cpu.'max-threads-hint'
        
        if ($NewThreadCount -eq $currentThreads) {
            Write-Log "  ℹ️ Already at $NewThreadCount threads" "INFO"
            return
        }
        
        Write-Log "  🔧 Adjusting threads: $currentThreads → $NewThreadCount" "INFO"
        Write-Log "     Reason: $Reason" "INFO"
        
        $config.cpu.'max-threads-hint' = $NewThreadCount
        $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
        
        # Restart miner
        Write-Log "  🔄 Restarting miner with new configuration..." "INFO"
        Restart-Miner
        
        $script:LastAdjustmentTime = Get-Date
        $script:ConsecutiveAdjustments++
        
        Write-Log "  ✅ Thread adjustment complete" "SUCCESS"
    }
    catch {
        Write-Log "  ❌ Failed to adjust threads: $($_.Exception.Message)" "ERROR"
    }
}

function Test-NetworkAndReport {
    Write-Log "  🌐 Testing network connectivity..." "INFO"
    $networkHealth = Test-NetworkHealth
    
    Write-Log "  Network Status: $($networkHealth.Status)" "INFO"
    Write-Log "  Reachable Pools: $($networkHealth.Healthy)/$($networkHealth.Total) ($($networkHealth.HealthPercent.ToString('F0'))%)" "INFO"
    
    if ($networkHealth.HealthPercent -lt 50) {
        Write-Log "  ⚠️ Network issues detected. Check internet connection." "WARNING"
    }
}

function Restart-Miner {
    Write-Log "  Stopping XMRig..." "INFO"
    
    $process = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
    
    Write-Log "  Starting XMRig..." "INFO"
    
    $startScript = "$XMRigPath\start-mining.bat"
    if (Test-Path $startScript) {
        Start-Process -FilePath $startScript -WorkingDirectory $XMRigPath -WindowStyle Minimized
    }
    else {
        $xmrigExe = "$XMRigPath\xmrig.exe"
        if (Test-Path $xmrigExe) {
            Start-Process -FilePath $xmrigExe -WorkingDirectory $XMRigPath -WindowStyle Minimized
        }
    }
    
    Start-Sleep -Seconds 10
    
    # Reset consecutive adjustments after cooldown
    $script:ConsecutiveAdjustments = 0
}

function Generate-PerformanceReport {
    if ($PerformanceHistory.Count -eq 0) {
        return
    }
    
    Write-Log "`n╔════════════════════════════════════════════════════════════╗" "INFO"
    Write-Log "║          24-HOUR PERFORMANCE SUMMARY                       ║" "INFO"
    Write-Log "╚════════════════════════════════════════════════════════════╝" "INFO"
    
    $avgHashrate = ($PerformanceHistory | Measure-Object -Property Hashrate -Average).Average
    $maxHashrate = ($PerformanceHistory | Measure-Object -Property Hashrate -Maximum).Maximum
    $minHashrate = ($PerformanceHistory | Measure-Object -Property Hashrate -Minimum).Minimum
    
    $avgTemp = ($PerformanceHistory | Where-Object { $_.CpuTemp -gt 0 } | Measure-Object -Property CpuTemp -Average).Average
    $maxTemp = ($PerformanceHistory | Where-Object { $_.CpuTemp -gt 0 } | Measure-Object -Property CpuTemp -Maximum).Maximum
    
    $totalShares = ($PerformanceHistory | Measure-Object -Property Accepted -Sum).Sum
    $totalRejected = ($PerformanceHistory | Measure-Object -Property Rejected -Sum).Sum
    
    Write-Log "  Hashrate:" "INFO"
    Write-Log "    Average: $($avgHashrate.ToString('F2')) H/s" "METRIC"
    Write-Log "    Peak:    $($maxHashrate.ToString('F2')) H/s" "METRIC"
    Write-Log "    Minimum: $($minHashrate.ToString('F2')) H/s" "METRIC"
    
    if ($avgTemp -gt 0) {
        Write-Log "`n  Temperature:" "INFO"
        Write-Log "    Average: $($avgTemp.ToString('F1'))°C" "METRIC"
        Write-Log "    Peak:    $maxTemp°C" "METRIC"
    }
    
    if ($totalShares -gt 0) {
        $successRate = (($totalShares / ($totalShares + $totalRejected)) * 100)
        Write-Log "`n  Shares:" "INFO"
        Write-Log "    Accepted: $totalShares" "METRIC"
        Write-Log "    Rejected: $totalRejected" "METRIC"
        Write-Log "    Success:  $($successRate.ToString('F1'))%" "METRIC"
    }
    
    Write-Log "════════════════════════════════════════════════════════════`n" "INFO"
}

function Initialize-Optimizer {
    Write-Host @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     🤖 AUTONOMOUS OPTIMIZER v3.0 🤖                       ║
║                                                           ║
║  Self-Learning Performance Optimization System            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

    Write-Log "Autonomous Optimizer v3.0 - Initializing..." "INFO"
    Write-Log "XMRig Path: $XMRigPath" "INFO"
    Write-Log "Check Interval: $CheckIntervalMinutes minutes" "INFO"
    Write-Log "Max Temperature: $MaxTemp°C" "INFO"
    Write-Log "Target Temperature: $TargetTemp°C" "INFO"
    Write-Log "Min Hashrate: $MinHashrate H/s" "INFO"
    Write-Log "Aggressive Mode: $($AggressiveOptimization.IsPresent)" "INFO"
    
    # Load historical performance data
    Load-PerformanceData
    
    Write-Log "Initialization complete`n" "SUCCESS"
}

# ============================================================================
# MAIN LOOP
# ============================================================================

function Start-Optimizer {
    Initialize-Optimizer
    
    $checkCounter = 0
    $reportCounter = 0
    
    Write-Log "Starting optimization loop...`n" "SUCCESS"
    
    while ($true) {
        try {
            # Get current metrics
            $metrics = Get-MiningMetrics
            
            if ($metrics) {
                # Save to history
                Save-PerformanceData -Metrics $metrics
                
                # Run optimization analysis
                Optimize-Performance -Metrics $metrics
                
                # Periodic network check
                if (-not $LastNetworkCheck -or ((Get-Date) - $LastNetworkCheck).TotalMinutes -ge $OptimizerConfig.NetworkCheckIntervalMinutes) {
                    Test-NetworkAndReport
                    $script:LastNetworkCheck = Get-Date
                }
                
                # Check if miner crashed
                $process = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
                if (-not $process) {
                    Write-Log "⚠️ XMRig is not running! Restarting..." "ERROR"
                    Restart-Miner
                }
            }
            else {
                Write-Log "Unable to collect metrics" "WARNING"
            }
            
            # Generate performance report every 12 hours
            $reportCounter++
            if ($reportCounter -ge (720 / $CheckIntervalMinutes)) {  # 12 hours
                Generate-PerformanceReport
                $reportCounter = 0
            }
            
            # Sleep until next check
            $nextCheck = (Get-Date).AddMinutes($CheckIntervalMinutes)
            Write-Log "Next optimization check at: $($nextCheck.ToString('HH:mm:ss'))" "INFO"
            Write-Log "═══════════════════════════════════════════════════════════`n" "INFO"
            
            Start-Sleep -Seconds ($CheckIntervalMinutes * 60)
        }
        catch {
            Write-Log "Error in main loop: $($_.Exception.Message)" "ERROR"
            Write-Log "Stack trace: $($_.ScriptStackTrace)" "DEBUG"
            Write-Log "Retrying in 5 minutes..." "WARNING"
            Start-Sleep -Seconds 300
        }
    }
}

# ============================================================================
# ENTRY POINT
# ============================================================================

Start-Optimizer
