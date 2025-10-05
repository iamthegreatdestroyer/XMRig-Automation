<#
.SYNOPSIS
    Checks XMRig mining status and displays detailed statistics.

.DESCRIPTION
    This script checks if XMRig is running, parses the log file for hashrate
    and share statistics, and displays a formatted status report with ASCII art.

.EXAMPLE
    .\check-status.ps1
    Displays the current mining status.

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
#>

param(
    [string]$XMRigPath = "C:\XMRig"
)

# Function to display ASCII art header
function Show-Header {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                               ║" -ForegroundColor Cyan
    Write-Host "║              ██╗  ██╗███╗   ███╗██████╗ ██╗ ██████╗          ║" -ForegroundColor Cyan
    Write-Host "║              ╚██╗██╔╝████╗ ████║██╔══██╗██║██╔════╝          ║" -ForegroundColor Cyan
    Write-Host "║               ╚███╔╝ ██╔████╔██║██████╔╝██║██║  ███╗         ║" -ForegroundColor Cyan
    Write-Host "║               ██╔██╗ ██║╚██╔╝██║██╔══██╗██║██║   ██║         ║" -ForegroundColor Cyan
    Write-Host "║              ██╔╝ ██╗██║ ╚═╝ ██║██║  ██║██║╚██████╔╝         ║" -ForegroundColor Cyan
    Write-Host "║              ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝ ╚═════╝          ║" -ForegroundColor Cyan
    Write-Host "║                                                               ║" -ForegroundColor Cyan
    Write-Host "║                  Monero Mining Status Monitor                 ║" -ForegroundColor Cyan
    Write-Host "║                        RyzenRig                               ║" -ForegroundColor Cyan
    Write-Host "║                                                               ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

# Function to check if XMRig process is running
function Get-MiningStatus {
    $process = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if ($process) {
        return @{
            Running = $true
            ProcessId = $process.Id
            StartTime = $process.StartTime
            CPUUsage = [math]::Round($process.CPU, 2)
            MemoryMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
        }
    }
    return @{ Running = $false }
}

# Function to parse log file for statistics
function Get-MiningStats {
    param([string]$LogPath)
    
    if (-not (Test-Path $LogPath)) {
        return $null
    }
    
    $stats = @{
        Hashrate = "N/A"
        Hashrate10s = "N/A"
        Hashrate60s = "N/A"
        Hashrate15m = "N/A"
        AcceptedShares = 0
        RejectedShares = 0
        PoolStatus = "Unknown"
        LastLogTime = "N/A"
    }
    
    try {
        # Read last 100 lines for recent stats
        $logLines = Get-Content $LogPath -Tail 100 -ErrorAction SilentlyContinue
        
        # Parse hashrate (look for speed lines)
        $speedLine = $logLines | Where-Object { $_ -match "speed.*10s/60s/15m" } | Select-Object -Last 1
        if ($speedLine -match "(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)") {
            $stats.Hashrate10s = "$($matches[1]) H/s"
            $stats.Hashrate60s = "$($matches[2]) H/s"
            $stats.Hashrate15m = "$($matches[3]) H/s"
            $stats.Hashrate = "$($matches[2]) H/s"  # Use 60s average as primary
        }
        
        # Parse accepted shares
        $acceptedLines = $logLines | Where-Object { $_ -match "accepted.*\((\d+)/\d+\)" }
        if ($acceptedLines) {
            $lastAccepted = $acceptedLines | Select-Object -Last 1
            if ($lastAccepted -match "\((\d+)/(\d+)\)") {
                $stats.AcceptedShares = [int]$matches[1]
                $totalShares = [int]$matches[2]
                $stats.RejectedShares = $totalShares - $stats.AcceptedShares
            }
        }
        
        # Check pool connection status
        $poolLine = $logLines | Where-Object { $_ -match "use pool" } | Select-Object -Last 1
        if ($poolLine -match "xmrpool\.eu") {
            $stats.PoolStatus = "Connected"
        }
        
        # Get last log timestamp
        $lastLine = $logLines | Select-Object -Last 1
        if ($lastLine -match "^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})") {
            $stats.LastLogTime = $matches[1]
        }
        
    } catch {
        Write-Warning "Error parsing log file: $_"
    }
    
    return $stats
}

# Function to display status information
function Show-Status {
    param(
        [hashtable]$Status,
        [hashtable]$Stats
    )
    
    # Mining Status
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor White
    Write-Host "║                      MINING STATUS                            ║" -ForegroundColor White
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor White
    Write-Host ""
    
    if ($Status.Running) {
        Write-Host "  Status:       " -NoNewline
        Write-Host "RUNNING ✓" -ForegroundColor Green
        Write-Host "  Process ID:   $($Status.ProcessId)" -ForegroundColor Gray
        Write-Host "  Started:      $($Status.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
        
        $uptime = (Get-Date) - $Status.StartTime
        Write-Host "  Uptime:       $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m $($uptime.Seconds)s" -ForegroundColor Gray
        Write-Host "  CPU Usage:    $($Status.CPUUsage)s" -ForegroundColor Gray
        Write-Host "  Memory:       $($Status.MemoryMB) MB" -ForegroundColor Gray
    } else {
        Write-Host "  Status:       " -NoNewline
        Write-Host "STOPPED ✗" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Mining is not currently running." -ForegroundColor Yellow
        Write-Host "  Run 'start-mining.bat' to begin mining." -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    # Performance Statistics
    if ($Stats) {
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor White
        Write-Host "║                   PERFORMANCE STATISTICS                      ║" -ForegroundColor White
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor White
        Write-Host ""
        
        Write-Host "  Current Hashrate (60s avg):  " -NoNewline
        if ($Stats.Hashrate60s -ne "N/A") {
            Write-Host $Stats.Hashrate60s -ForegroundColor Green
        } else {
            Write-Host $Stats.Hashrate60s -ForegroundColor Yellow
        }
        
        Write-Host "  Hashrate (10s):               $($Stats.Hashrate10s)" -ForegroundColor Gray
        Write-Host "  Hashrate (15m):               $($Stats.Hashrate15m)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Accepted Shares:              " -NoNewline
        Write-Host $Stats.AcceptedShares -ForegroundColor Green
        Write-Host "  Rejected Shares:              " -NoNewline
        if ($Stats.RejectedShares -eq 0) {
            Write-Host $Stats.RejectedShares -ForegroundColor Green
        } else {
            Write-Host $Stats.RejectedShares -ForegroundColor Yellow
        }
        
        if ($Stats.AcceptedShares -gt 0) {
            $acceptanceRate = [math]::Round(($Stats.AcceptedShares / ($Stats.AcceptedShares + $Stats.RejectedShares)) * 100, 2)
            Write-Host "  Acceptance Rate:              $acceptanceRate%" -ForegroundColor Cyan
        }
        
        Write-Host ""
        Write-Host "  Pool Status:                  " -NoNewline
        if ($Stats.PoolStatus -eq "Connected") {
            Write-Host $Stats.PoolStatus -ForegroundColor Green
        } else {
            Write-Host $Stats.PoolStatus -ForegroundColor Yellow
        }
        Write-Host "  Pool:                         xmrpool.eu:3333" -ForegroundColor Gray
        Write-Host "  Last Log Update:              $($Stats.LastLogTime)" -ForegroundColor Gray
        Write-Host ""
    }
    
    # Quick Actions
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor White
    Write-Host "║                       QUICK ACTIONS                           ║" -ForegroundColor White
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor White
    Write-Host ""
    Write-Host "  View Balance:    " -NoNewline
    Write-Host "https://xmrpool.eu/#/dashboard" -ForegroundColor Cyan
    Write-Host "  Wallet:          4Anom...ycu4HyvWVSx" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor White
    Write-Host "    start-mining.bat         - Start mining" -ForegroundColor Gray
    Write-Host "    stop-mining.bat          - Stop mining" -ForegroundColor Gray
    Write-Host "    view-logs.bat            - View live logs" -ForegroundColor Gray
    Write-Host "    monitor-performance.ps1  - Real-time monitoring" -ForegroundColor Gray
    Write-Host ""
}

# Function to display last log lines
function Show-RecentLogs {
    param([string]$LogPath, [int]$Lines = 20)
    
    if (-not (Test-Path $LogPath)) {
        return
    }
    
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor White
    Write-Host "║                    RECENT LOG ENTRIES                         ║" -ForegroundColor White
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor White
    Write-Host ""
    
    $recentLogs = Get-Content $LogPath -Tail $Lines -ErrorAction SilentlyContinue
    foreach ($line in $recentLogs) {
        # Color code log lines
        if ($line -match "accepted") {
            Write-Host "  $line" -ForegroundColor Green
        } elseif ($line -match "error|failed|rejected") {
            Write-Host "  $line" -ForegroundColor Red
        } elseif ($line -match "speed") {
            Write-Host "  $line" -ForegroundColor Cyan
        } else {
            Write-Host "  $line" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

# Main execution
try {
    Clear-Host
    Show-Header
    
    # Check mining status
    $status = Get-MiningStatus
    
    # Parse log file
    $logPath = Join-Path $XMRigPath "xmrig.log"
    $stats = Get-MiningStats -LogPath $logPath
    
    # Display status
    Show-Status -Status $status -Stats $stats
    
    # Show recent logs if mining is running
    if ($status.Running) {
        Show-RecentLogs -LogPath $logPath -Lines 20
    }
    
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    exit 0
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
