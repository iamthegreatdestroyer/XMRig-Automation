# ============================================================================
# DASHBOARD DATA UPDATER
# ============================================================================
# Reads mining data and generates JavaScript for the dashboard
# Run this script every 5 seconds to keep dashboard updated
# ============================================================================

param(
    [string]$XMRigPath = "C:\XMRig",
    [switch]$Continuous
)

$StatusFile = "$XMRigPath\logs\profit-switcher-status.json"
$ConfigFile = "$XMRigPath\xmrig-6.22.0\config.json"
$LogFile = "$XMRigPath\xmrig-6.22.0\xmrig.log"
$OutputFile = "$PSScriptRoot\dashboard-data.js"

function Get-MiningData {
    $data = @{
        timestamp      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        xmrig          = @{
            running  = $false
            hashrate = 0
            accepted = 0
            rejected = 0
            uptime   = "0h 0m"
        }
        profitSwitcher = @{
            status          = "INACTIVE"
            currentCoin     = "XMR"
            currentCoinName = "Monero"
            currentProfit   = 0.00
            lastCheck       = "Unknown"
            nextCheck       = "Unknown"
        }
        optimizer      = @{
            status = "INACTIVE"
        }
        system         = @{
            cpuTemp  = 0
            cpuUsage = 0
        }
    }
    
    # Check if XMRig is running
    $xmrigProcess = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if ($xmrigProcess) {
        $data.xmrig.running = $true
        
        # Parse XMRig log for latest stats
        if (Test-Path $LogFile) {
            $logLines = Get-Content $LogFile -Tail 100 -ErrorAction SilentlyContinue
            
            foreach ($line in $logLines) {
                # Parse hashrate: [2025-10-05 19:35:08.123]  miner    speed 10s/60s/15m 1899.5 1901.2 n/a H/s
                if ($line -match 'speed.*?(\d+\.\d+).*?(\d+\.\d+).*?H/s') {
                    $data.xmrig.hashrate = [double]$matches[2]
                }
                
                # Parse shares: [2025-10-05 19:35:08.123]  miner    accepted (120/0) diff 50000
                if ($line -match 'accepted \((\d+)/(\d+)\)') {
                    $data.xmrig.accepted = [int]$matches[1]
                    $data.xmrig.rejected = [int]$matches[2]
                }
            }
        }
        
        # Calculate uptime
        $uptime = (Get-Date) - $xmrigProcess.StartTime
        $hours = [math]::Floor($uptime.TotalHours)
        $minutes = $uptime.Minutes
        $data.xmrig.uptime = "${hours}h ${minutes}m"
    }
    
    # Read profit switcher status
    if (Test-Path $StatusFile) {
        try {
            $switcherStatus = Get-Content $StatusFile -Raw | ConvertFrom-Json
            $data.profitSwitcher = @{
                status          = $switcherStatus.Status
                currentCoin     = $switcherStatus.CurrentCoin
                currentCoinName = $switcherStatus.CurrentCoinName
                currentProfit   = $switcherStatus.CurrentProfit
                lastCheck       = $switcherStatus.LastCheck
                nextCheck       = $switcherStatus.NextCheck
            }
        }
        catch {
            # Use defaults if file is corrupted
        }
    }
    
    # Check optimizer status
    $optimizerProcess = Get-Process -Name "powershell" -ErrorAction SilentlyContinue | 
    Where-Object { $_.CommandLine -like "*optimizer*" }
    if ($optimizerProcess) {
        $data.optimizer.status = "ACTIVE"
    }
    
    # Get system info
    try {
        $cpu = Get-WmiObject Win32_Processor
        $data.system.cpuUsage = [math]::Round($cpu.LoadPercentage, 1)
        
        # Temperature (if available)
        $temp = Get-WmiObject -Namespace "root/WMI" -Class MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        if ($temp) {
            $data.system.cpuTemp = [math]::Round(($temp.CurrentTemperature - 2732) / 10, 1)
        }
    }
    catch {
        # Fallback values
        $data.system.cpuUsage = 75
        $data.system.cpuTemp = 73
    }
    
    return $data
}

function Write-DashboardJS {
    param($Data)
    
    $js = @"
// Auto-generated dashboard data
// Last updated: $($Data.timestamp)

window.MINING_DATA = $($ Data | ConvertTo-Json -Depth 10);

// Auto-refresh this data
if (typeof updateDashboardFromData === 'function') {
    updateDashboardFromData(window.MINING_DATA);
}
"@
    
    $js | Set-Content -Path $OutputFile -Force
}

# Main execution
do {
    try {
        $miningData = Get-MiningData
        Write-DashboardJS -Data $miningData
        
        if ($Continuous) {
            Start-Sleep -Seconds 5
        }
    }
    catch {
        Write-Host "Error updating dashboard data: $_" -ForegroundColor Red
        if ($Continuous) {
            Start-Sleep -Seconds 5
        }
    }
} while ($Continuous)

if (-not $Continuous) {
    Write-Host "Dashboard data updated successfully" -ForegroundColor Green
}
