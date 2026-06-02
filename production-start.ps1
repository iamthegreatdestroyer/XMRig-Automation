#!/usr/bin/env powershell
<#
.SYNOPSIS
    XMRig Automation - Production Startup Script
.DESCRIPTION
    Starts all XMRig Automation services in production mode.
    This script ensures all services start in the correct order.
.AUTHOR
    XMRig Automation
.VERSION
    2.0
#>

param(
    [switch]$Restart,
    [switch]$Stop,
    [switch]$Status
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DashboardDir = Join-Path $ScriptDir "dashboard"
$ConfigDir = Join-Path $ScriptDir "config"
$XMRigRunDir = "C:\XMRig\xmrig-6.22.0"
$RuntimeConfigPath = "$XMRigRunDir\config.json"
$SecureStoragePath = "$env:APPDATA\XMRig\secure"
$RuntimeTokenFile  = "$SecureStoragePath\api-token.txt"

# ============================================================================
# SECURE RUNTIME CONFIG INJECTION
# ============================================================================
# Reads the repo's config template (no secrets), injects the DPAPI-decrypted
# wallet and API token at runtime, writes to XMRig's working directory.
# The running config in C:\XMRig\xmrig-6.22.0\ is NOT committed to git.

function Invoke-SecureConfigInjection {
    # Ensure token exists; generate if first run
    if (-not (Test-Path $RuntimeTokenFile)) {
        Write-Host "  No API token found — generating new token..." -ForegroundColor Yellow
        . "$ScriptDir\security\Generate-APIToken.ps1"
    }
    $apiToken = (Get-Content $RuntimeTokenFile -Raw).Trim()

    # Load repo config template
    $templatePath = "$ConfigDir\config.json"
    if (-not (Test-Path $templatePath)) {
        Write-Host "  ERROR: Config template not found: $templatePath" -ForegroundColor Red
        return $false
    }
    $config = Get-Content $templatePath -Raw | ConvertFrom-Json

    # Inject API token
    $config.http.'access-token' = $apiToken

    # Inject wallet from DPAPI if using placeholder
    if ($config.pools[0].user -eq "__SECURE_WALLET__") {
        . "$ScriptDir\security\Secure-WalletManager.ps1" | Out-Null
        $wallet = Unprotect-WalletAddress
        if ($wallet) {
            $config.pools | ForEach-Object { if ($_.user -eq "__SECURE_WALLET__") { $_.user = $wallet } }
            Write-Host "  Wallet injected from DPAPI secure storage." -ForegroundColor Green
        } else {
            Write-Host "  WARNING: Could not decrypt wallet. Check DPAPI storage." -ForegroundColor Yellow
        }
    }

    # Write runtime config to XMRig working directory
    $config | ConvertTo-Json -Depth 10 | Set-Content $RuntimeConfigPath -Force
    Write-Host "  Runtime config written: $RuntimeConfigPath" -ForegroundColor Green
    return $true
}

# Service definitions
$Services = @(
    @{
        Name         = "XMRigMiner"
        ProcessName  = "xmrig"
        StartCommand = "$XMRigRunDir\xmrig.exe --config=config.json"
        WorkingDir   = $XMRigRunDir
        Description  = "XMRig cryptocurrency miner"
    },
    @{
        Name         = "PrometheusMetrics"
        ProcessName  = "python"
        StartCommand = "python prometheus_metrics_server.py"
        WorkingDir   = $DashboardDir
        Description  = "Prometheus metrics server"
    },
    @{
        Name         = "WebDashboard"
        ProcessName  = "python"
        StartCommand = "python web_dashboard.py"
        WorkingDir   = $DashboardDir
        Description  = "Web-based monitoring dashboard"
    },
    @{
        Name         = "PoolFlightTable"
        ProcessName  = "python"
        StartCommand = "python pool_flight_table.py --daemon"
        WorkingDir   = (Join-Path $ScriptDir "intelligence")
        Description  = "Pool latency flight table (dynamic routing)"
    },
    @{
        Name         = "PriorityController"
        ProcessName  = "powershell"
        StartCommand = "powershell -ExecutionPolicy Bypass -File priority_controller.ps1 -Silent"
        WorkingDir   = (Join-Path $ScriptDir "intelligence")
        Description  = "Adaptive process priority (user-idle detection)"
    }
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Header {
    param([string]$Title)
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
}

function Get-ServiceStatus {
    param([hashtable]$Service)
    $processes = Get-Process -Name $Service.ProcessName -ErrorAction SilentlyContinue
    if ($processes) {
        $matchingProcess = $processes | Where-Object {
            $_.CommandLine -like "*$($Service.StartCommand.Split(' ')[-1])*"
        }
        if ($matchingProcess) {
            return @{
                Running = $true
                Process = $matchingProcess
                PID     = $matchingProcess.Id
            }
        }
    }
    return @{ Running = $false; Process = $null; PID = $null }
}

function Stop-Service {
    param([hashtable]$Service)
    Write-Host "Stopping $($Service.Name)..." -ForegroundColor Yellow
    $status = Get-ServiceStatus -Service $Service
    if ($status.Running) {
        Stop-Process -Id $status.PID -Force
        Start-Sleep -Seconds 2
        Write-Host "  ✓ Stopped $($Service.Name) (PID: $($status.PID))" -ForegroundColor Green
    }
    else {
        Write-Host "  - $($Service.Name) was not running" -ForegroundColor Gray
    }
}

function Start-Service {
    param([hashtable]$Service)
    Write-Host "Starting $($Service.Name)..." -ForegroundColor Yellow
    $status = Get-ServiceStatus -Service $Service
    if (-not $status.Running) {
        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $Service.StartCommand.Split(' ')[0]
            $startInfo.Arguments = ($Service.StartCommand -split ' ', 2)[1]
            $startInfo.WorkingDirectory = $Service.WorkingDir
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            $process.Start() | Out-Null

            Start-Sleep -Seconds 3

            $newStatus = Get-ServiceStatus -Service $Service
            if ($newStatus.Running) {
                Write-Host "  ✓ Started $($Service.Name) (PID: $($newStatus.PID))" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ Failed to start $($Service.Name)" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "  ✗ Error starting $($Service.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  - $($Service.Name) is already running (PID: $($status.PID))" -ForegroundColor Gray
    }
}

function Show-Status {
    Write-Header "SERVICE STATUS"
    foreach ($service in $Services) {
        $status = Get-ServiceStatus -Service $service
        $statusText = if ($status.Running) { "RUNNING" } else { "STOPPED" }
        $statusColor = if ($status.Running) { "Green" } else { "Red" }
        $pidText = if ($status.PID) { "(PID: $($status.PID))" } else { "" }

        Write-Host "$($service.Name): " -NoNewline
        Write-Host "$statusText $pidText" -ForegroundColor $statusColor
        Write-Host "  $($service.Description)" -ForegroundColor Gray
        Write-Host ""
    }

    # Show port status
    Write-Host "Port Status:" -ForegroundColor Yellow
    $ports = @(
        @{ Port = 24808; Service = "XMRig HTTP API" },
        @{ Port = 29100; Service = "Prometheus Metrics" },
        @{ Port = 23000; Service = "Web Dashboard" }
    )

    foreach ($portInfo in $ports) {
        try {
            $connection = New-Object System.Net.Sockets.TcpClient
            $connection.Connect("127.0.0.1", $portInfo.Port)
            $connection.Close()
            Write-Host "  $($portInfo.Port): OPEN ($($portInfo.Service))" -ForegroundColor Green
        }
        catch {
            Write-Host "  $($portInfo.Port): CLOSED ($($portInfo.Service))" -ForegroundColor Red
        }
    }
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

if ($Status) {
    Show-Status
    exit
}

if ($Stop) {
    Write-Header "STOPPING XMRIG AUTOMATION SERVICES"
    foreach ($service in $Services) {
        Stop-Service -Service $service
    }
    Write-Host "All services stopped." -ForegroundColor Green
    exit
}

if ($Restart) {
    Write-Header "RESTARTING XMRIG AUTOMATION SERVICES"
    foreach ($service in $Services) {
        Stop-Service -Service $service
        Start-Sleep -Seconds 2
        Start-Service -Service $service
    }
}
else {
    Write-Header "STARTING XMRIG AUTOMATION PRODUCTION SERVICES"
    Write-Host "Injecting secure runtime configuration..." -ForegroundColor Yellow
    $injected = Invoke-SecureConfigInjection
    if (-not $injected) {
        Write-Host "WARNING: Config injection failed. Proceeding with existing runtime config." -ForegroundColor Yellow
    }
    foreach ($service in $Services) {
        Start-Service -Service $service
    }
}

Write-Host ""
Show-Status

Write-Host ""
Write-Host "Production URLs:" -ForegroundColor Cyan
Write-Host "  Dashboard:    http://localhost:23000" -ForegroundColor White
Write-Host "  Metrics:      http://localhost:29100/metrics" -ForegroundColor White
Write-Host "  XMRig API:    http://localhost:24808" -ForegroundColor White

Write-Host ""
Write-Host "To check status: .\production-start.ps1 -Status" -ForegroundColor Yellow
Write-Host "To restart all:  .\production-start.ps1 -Restart" -ForegroundColor Yellow
Write-Host "To stop all:     .\production-start.ps1 -Stop" -ForegroundColor Yellow

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  XMRIG AUTOMATION - PRODUCTION MODE ACTIVE" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan