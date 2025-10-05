<#
.SYNOPSIS
    Real-time performance monitoring for XMRig mining.

.DESCRIPTION
    Monitors XMRig performance including CPU usage, temperature, memory,
    hashrate trends, and share acceptance rate. Updates display every 5 seconds.
    Alerts if temperature exceeds 85°C or hashrate drops below 1500 H/s.

.PARAMETER XMRigPath
    Path to XMRig installation directory.

.PARAMETER ExportPath
    Optional path to export performance data to CSV.

.PARAMETER RefreshInterval
    Display refresh interval in seconds (default: 5).

.EXAMPLE
    .\monitor-performance.ps1
    Starts real-time monitoring with default settings.

.EXAMPLE
    .\monitor-performance.ps1 -ExportPath "C:\Logs\performance.csv"
    Monitors and exports data to CSV.

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
    Press Ctrl+C to exit monitoring.
#>

param(
    [string]$XMRigPath = "C:\XMRig",
    [string]$ExportPath = "",
    [int]$RefreshInterval = 5
)

# Constants
$TEMP_ALERT_THRESHOLD = 85
$HASHRATE_ALERT_THRESHOLD = 1500

# Performance history storage
$script:HashrateHistory = @()
$script:MaxHistorySize = 720  # 1 hour at 5-second intervals

# Function to get CPU temperature (Windows 11)
function Get-CPUTemperature {
    try {
        # Try OpenHardwareMonitor WMI (requires OHM running)
        $temp = Get-WmiObject -Namespace "root\OpenHardwareMonitor" -Class Sensor -ErrorAction SilentlyContinue |
                Where-Object { $_.SensorType -eq "Temperature" -and $_.Name -like "*CPU*" } |
                Select-Object -First 1 -ExpandProperty Value
        
        if ($temp) {
            return [math]::Round($temp, 1)
        }
        
        # Alternative: Try MSAcpi_ThermalZoneTemperature (less accurate)
        $thermal = Get-WmiObject -Namespace "root\WMI" -Class MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue |
                   Select-Object -First 1 -ExpandProperty CurrentTemperature
        
        if ($thermal) {
            # Convert from tenths of Kelvin to Celsius
            return [math]::Round(($thermal / 10) - 273.15, 1)
        }
        
        return "N/A"
    } catch {
        return "N/A"
    }
}

# Function to parse current hashrate from log
function Get-CurrentHashrate {
    param([string]$LogPath)
    
    if (-not (Test-Path $LogPath)) {
        return $null
    }
    
    try {
        $logLines = Get-Content $LogPath -Tail 50 -ErrorAction SilentlyContinue
        $speedLine = $logLines | Where-Object { $_ -match "speed.*10s/60s/15m" } | Select-Object -Last 1
        
        if ($speedLine -match "(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)") {
            return @{
                Hashrate10s = [double]$matches[1]
                Hashrate60s = [double]$matches[2]
                Hashrate15m = [double]$matches[3]
            }
        }
        
        return $null
    } catch {
        return $null
    }
}

# Function to get share statistics
function Get-ShareStats {
    param([string]$LogPath)
    
    if (-not (Test-Path $LogPath)) {
        return @{ Accepted = 0; Rejected = 0; AcceptanceRate = 0 }
    }
    
    try {
        $logLines = Get-Content $LogPath -Tail 100 -ErrorAction SilentlyContinue
        $acceptedLines = $logLines | Where-Object { $_ -match "accepted.*\((\d+)/(\d+)\)" }
        
        if ($acceptedLines) {
            $lastAccepted = $acceptedLines | Select-Object -Last 1
            if ($lastAccepted -match "\((\d+)/(\d+)\)") {
                $accepted = [int]$matches[1]
                $total = [int]$matches[2]
                $rejected = $total - $accepted
                $rate = if ($total -gt 0) { [math]::Round(($accepted / $total) * 100, 2) } else { 0 }
                
                return @{
                    Accepted = $accepted
                    Rejected = $rejected
                    Total = $total
                    AcceptanceRate = $rate
                }
            }
        }
        
        return @{ Accepted = 0; Rejected = 0; Total = 0; AcceptanceRate = 0 }
    } catch {
        return @{ Accepted = 0; Rejected = 0; Total = 0; AcceptanceRate = 0 }
    }
}

# Function to display ASCII art graph
function Show-HashrateGraph {
    param([array]$History, [int]$Width = 50, [int]$Height = 10)
    
    if ($History.Count -lt 2) {
        Write-Host "  Collecting data..." -ForegroundColor Yellow
        return
    }
    
    $max = ($History | Measure-Object -Maximum).Maximum
    $min = ($History | Measure-Object -Minimum).Minimum
    $range = $max - $min
    
    if ($range -eq 0) { $range = 1 }
    
    # Take last $Width data points
    $dataPoints = $History | Select-Object -Last $Width
    
    Write-Host "  Hashrate Trend (Last $($dataPoints.Count * $RefreshInterval)s)" -ForegroundColor Cyan
    Write-Host "  Max: $([math]::Round($max, 1)) H/s  Min: $([math]::Round($min, 1)) H/s  Range: $([math]::Round($range, 1)) H/s" -ForegroundColor Gray
    Write-Host ""
    
    # Draw graph
    for ($h = $Height; $h -ge 0; $h--) {
        $threshold = $min + ($range * $h / $Height)
        Write-Host "  $([math]::Round($threshold, 0).ToString().PadLeft(5)) |" -NoNewline -ForegroundColor Gray
        
        foreach ($point in $dataPoints) {
            if ($point -ge $threshold) {
                Write-Host "█" -NoNewline -ForegroundColor Green
            } else {
                Write-Host " " -NoNewline
            }
        }
        Write-Host ""
    }
    
    Write-Host "        +" -NoNewline -ForegroundColor Gray
    Write-Host ("-" * $dataPoints.Count) -ForegroundColor Gray
    Write-Host ""
}

# Function to display monitoring dashboard
function Show-Dashboard {
    param(
        [hashtable]$ProcessInfo,
        [hashtable]$HashrateInfo,
        [hashtable]$ShareInfo,
        [double]$Temperature,
        [datetime]$Uptime
    )
    
    Clear-Host
    
    # Header
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "       XMRig PERFORMANCE MONITOR - Real-Time Dashboard" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Rig: RyzenRig  |  Pool: xmrpool.eu  |  Refresh: ${RefreshInterval}s" -ForegroundColor Gray
    Write-Host "  Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
    
    # Process Status
    Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "│ PROCESS STATUS                                              │" -ForegroundColor White
    Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor White
    
    if ($ProcessInfo) {
        $uptimeSpan = (Get-Date) - $Uptime
        Write-Host "  Status:    " -NoNewline
        Write-Host "RUNNING ✓" -ForegroundColor Green
        Write-Host "  PID:       $($ProcessInfo.Id)" -ForegroundColor Gray
        Write-Host "  Uptime:    $($uptimeSpan.Days)d $($uptimeSpan.Hours)h $($uptimeSpan.Minutes)m $($uptimeSpan.Seconds)s" -ForegroundColor Gray
        Write-Host "  CPU:       $([math]::Round($ProcessInfo.CPU, 2))s total" -ForegroundColor Gray
        Write-Host "  Memory:    $([math]::Round($ProcessInfo.WorkingSet64 / 1MB, 2)) MB" -ForegroundColor Gray
    } else {
        Write-Host "  Status:    " -NoNewline
        Write-Host "STOPPED ✗" -ForegroundColor Red
    }
    Write-Host ""
    
    # Hashrate
    Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "│ HASHRATE                                                    │" -ForegroundColor White
    Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor White
    
    if ($HashrateInfo) {
        Write-Host "  Current (60s):  " -NoNewline
        $hashrate = $HashrateInfo.Hashrate60s
        if ($hashrate -lt $HASHRATE_ALERT_THRESHOLD) {
            Write-Host "$([math]::Round($hashrate, 2)) H/s ⚠" -ForegroundColor Yellow
        } else {
            Write-Host "$([math]::Round($hashrate, 2)) H/s" -ForegroundColor Green
        }
        Write-Host "  10s Average:    $([math]::Round($HashrateInfo.Hashrate10s, 2)) H/s" -ForegroundColor Gray
        Write-Host "  15m Average:    $([math]::Round($HashrateInfo.Hashrate15m, 2)) H/s" -ForegroundColor Gray
    } else {
        Write-Host "  No hashrate data available" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Temperature & Alerts
    Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "│ SYSTEM METRICS                                              │" -ForegroundColor White
    Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor White
    Write-Host "  CPU Temp:       " -NoNewline
    if ($Temperature -ne "N/A") {
        if ($Temperature -ge $TEMP_ALERT_THRESHOLD) {
            Write-Host "$Temperature °C ⚠ HIGH!" -ForegroundColor Red
        } elseif ($Temperature -ge 75) {
            Write-Host "$Temperature °C ⚠" -ForegroundColor Yellow
        } else {
            Write-Host "$Temperature °C" -ForegroundColor Green
        }
    } else {
        Write-Host "N/A (Install OpenHardwareMonitor for temp monitoring)" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Share Statistics
    Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "│ SHARE STATISTICS                                            │" -ForegroundColor White
    Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor White
    Write-Host "  Accepted:       " -NoNewline
    Write-Host "$($ShareInfo.Accepted)" -ForegroundColor Green
    Write-Host "  Rejected:       " -NoNewline
    if ($ShareInfo.Rejected -eq 0) {
        Write-Host "$($ShareInfo.Rejected)" -ForegroundColor Green
    } else {
        Write-Host "$($ShareInfo.Rejected)" -ForegroundColor Yellow
    }
    Write-Host "  Acceptance:     $($ShareInfo.AcceptanceRate)%" -ForegroundColor Cyan
    Write-Host ""
    
    # Hashrate Graph
    Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "│ HASHRATE TREND                                              │" -ForegroundColor White
    Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor White
    Show-HashrateGraph -History $script:HashrateHistory -Width 50 -Height 8
    Write-Host ""
    
    # Alerts
    $hasAlerts = $false
    if ($HashrateInfo -and $HashrateInfo.Hashrate60s -lt $HASHRATE_ALERT_THRESHOLD) {
        if (-not $hasAlerts) {
            Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Red
            Write-Host "│ ⚠ ALERTS                                                    │" -ForegroundColor Red
            Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Red
            $hasAlerts = $true
        }
        Write-Host "  ⚠ Low hashrate detected ($([math]::Round($HashrateInfo.Hashrate60s, 2)) H/s < $HASHRATE_ALERT_THRESHOLD H/s)" -ForegroundColor Yellow
    }
    
    if ($Temperature -ne "N/A" -and $Temperature -ge $TEMP_ALERT_THRESHOLD) {
        if (-not $hasAlerts) {
            Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Red
            Write-Host "│ ⚠ ALERTS                                                    │" -ForegroundColor Red
            Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Red
            $hasAlerts = $true
        }
        Write-Host "  ⚠ High temperature detected ($Temperature °C >= $TEMP_ALERT_THRESHOLD °C)" -ForegroundColor Red
    }
    
    if ($hasAlerts) { Write-Host "" }
    
    # Footer
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Press Ctrl+C to exit  |  Next update in ${RefreshInterval}s" -ForegroundColor Gray
    Write-Host ""
}

# Function to export data to CSV
function Export-PerformanceData {
    param(
        [string]$Path,
        [hashtable]$Data
    )
    
    if (-not $Path) { return }
    
    try {
        $csvData = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Hashrate10s = $Data.Hashrate10s
            Hashrate60s = $Data.Hashrate60s
            Hashrate15m = $Data.Hashrate15m
            AcceptedShares = $Data.AcceptedShares
            RejectedShares = $Data.RejectedShares
            AcceptanceRate = $Data.AcceptanceRate
            Temperature = $Data.Temperature
            MemoryMB = $Data.MemoryMB
            CPUTime = $Data.CPUTime
        }
        
        $csvData | Export-Csv -Path $Path -Append -NoTypeInformation -Force
    } catch {
        Write-Warning "Failed to export to CSV: $_"
    }
}

# Main monitoring loop
try {
    Write-Host ""
    Write-Host "Starting XMRig Performance Monitor..." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to exit" -ForegroundColor Gray
    Write-Host ""
    Start-Sleep -Seconds 2
    
    $logPath = Join-Path $XMRigPath "xmrig.log"
    
    while ($true) {
        # Get process information
        $process = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
        
        if ($process) {
            # Get hashrate
            $hashrateInfo = Get-CurrentHashrate -LogPath $logPath
            
            # Get share statistics
            $shareInfo = Get-ShareStats -LogPath $logPath
            
            # Get temperature
            $temperature = Get-CPUTemperature
            
            # Update hashrate history
            if ($hashrateInfo) {
                $script:HashrateHistory += $hashrateInfo.Hashrate60s
                if ($script:HashrateHistory.Count -gt $script:MaxHistorySize) {
                    $script:HashrateHistory = $script:HashrateHistory | Select-Object -Last $script:MaxHistorySize
                }
            }
            
            # Display dashboard
            Show-Dashboard -ProcessInfo $process `
                          -HashrateInfo $hashrateInfo `
                          -ShareInfo $shareInfo `
                          -Temperature $temperature `
                          -Uptime $process.StartTime
            
            # Export to CSV if specified
            if ($ExportPath) {
                $exportData = @{
                    Hashrate10s = if ($hashrateInfo) { $hashrateInfo.Hashrate10s } else { 0 }
                    Hashrate60s = if ($hashrateInfo) { $hashrateInfo.Hashrate60s } else { 0 }
                    Hashrate15m = if ($hashrateInfo) { $hashrateInfo.Hashrate15m } else { 0 }
                    AcceptedShares = $shareInfo.Accepted
                    RejectedShares = $shareInfo.Rejected
                    AcceptanceRate = $shareInfo.AcceptanceRate
                    Temperature = $temperature
                    MemoryMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
                    CPUTime = [math]::Round($process.CPU, 2)
                }
                Export-PerformanceData -Path $ExportPath -Data $exportData
            }
            
        } else {
            Clear-Host
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
            Write-Host "  XMRig is not running!" -ForegroundColor Red
            Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Please start mining using start-mining.bat" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Waiting for XMRig to start..." -ForegroundColor Gray
            Write-Host ""
        }
        
        # Wait for next refresh
        Start-Sleep -Seconds $RefreshInterval
    }
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
