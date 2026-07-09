<#
.SYNOPSIS
    Creates a Windows scheduled task that runs the Prometheus metrics
    server continuously (Sprint 4.2, Sigma ecosystem federation).

.DESCRIPTION
    Registers a task that starts dashboard/prometheus_metrics_server.py
    and keeps it running continuously so sigma-box's Prometheus instance
    always has something to scrape. Unlike the nightly reflection and
    Ryzanstein sync tasks (which run once a day and exit), this needs a
    "keep it alive" pattern rather than a single daily trigger.

    Uses a Daily trigger with a 5-minute repetition over a 24-hour window
    (the same trigger *type* already proven to work for this machine's
    other two scheduled tasks) rather than an AtLogOn trigger -- AtLogOn
    was tried first and consistently failed with "Access is denied" even
    in a minimal, otherwise-identical configuration, which points to a
    local policy restriction on this machine rather than anything wrong
    with the task definition itself; not worth fighting further when an
    equally-effective alternative already works. Every 5 minutes, Task
    Scheduler attempts to (re)start the server; -MultipleInstances
    IgnoreNew means if it's already running, this is a harmless no-op,
    and if it crashed, this check-in relaunches it within 5 minutes.

    Binds to 0.0.0.0:29100 deliberately -- unlike Ryzanstein/Qdrant on the
    Debian box (which are loopback-only because nothing legitimate needs
    LAN access to them), this metrics endpoint's whole purpose is to be
    scraped by that box across the LAN, so it genuinely needs to be
    LAN-reachable, not just localhost.

.PARAMETER TaskName
    Name for the scheduled task.

.PARAMETER RepoPath
    Full path to the XMRig-Automation repository.

.EXAMPLE
    .\create-metrics-server-scheduled-task.ps1 -RepoPath "C:\Users\sgbil\XMRig-Automation"

.NOTES
    Author: XMRig Automation Project
    Does NOT require Administrator privileges.
#>

[CmdletBinding()]
param(
    [string]$TaskName = "XMRig Prometheus Metrics Server",

    [Parameter(Mandatory = $true)]
    [string]$RepoPath
)

Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  Prometheus Metrics Server -- Scheduled Task Configuration" -ForegroundColor White
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "[1/5] Verifying repository path..." -ForegroundColor Cyan
    $serverScript = Join-Path $RepoPath "dashboard\prometheus_metrics_server.py"
    if (-not (Test-Path $serverScript)) {
        throw "dashboard/prometheus_metrics_server.py not found under: $RepoPath"
    }
    Write-Host "  Found: $serverScript" -ForegroundColor Green
    Write-Host ""

    Write-Host "[2/5] Checking for existing task..." -ForegroundColor Cyan
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "  Task '$TaskName' already exists -- removing to re-register." -ForegroundColor Yellow
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    else {
        Write-Host "  No existing task found." -ForegroundColor Green
    }
    Write-Host ""

    Write-Host "[3/5] Creating task action..." -ForegroundColor Cyan
    $pythonExe = (Get-Command python).Source
    $dashboardDir = Join-Path $RepoPath "dashboard"
    $action = New-ScheduledTaskAction `
        -Execute $pythonExe `
        -Argument "prometheus_metrics_server.py" `
        -WorkingDirectory $dashboardDir
    Write-Host "  Action: $pythonExe prometheus_metrics_server.py (cwd: $dashboardDir)" -ForegroundColor Green
    Write-Host ""

    Write-Host "[4/5] Creating task trigger (daily + 5-minute repetition)..." -ForegroundColor Cyan
    $trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
    $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At "00:00" `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration (New-TimeSpan -Hours 24)).Repetition
    Write-Host "  Trigger: daily, re-checked every 5m (self-healing if the server dies)" -ForegroundColor Green
    Write-Host ""

    Write-Host "[5/5] Configuring task settings and principal..." -ForegroundColor Cyan
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero)  # zero = unlimited (this runs forever)

    $currentUser = "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal `
        -UserId $currentUser `
        -LogonType Interactive `
        -RunLevel Limited

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Continuously-running Prometheus metrics endpoint (:29100) for XMRig mining + Local Intelligence Layer observability (Sprint 4.2). Re-checked every 5 minutes; self-heals if it exits (IgnoreNew skips the check if it is already running)." `
        -ErrorAction Stop | Out-Null

    Write-Host "  Task registered for user: $currentUser" -ForegroundColor Green
    Write-Host ""

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host "  Scheduled Task Created Successfully" -ForegroundColor Green
    Write-Host "===========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Name:      $TaskName" -ForegroundColor Gray
    Write-Host "  State:     $($task.State)" -ForegroundColor Gray
    Write-Host "  Trigger:   Daily, re-checked every 5m (self-healing)" -ForegroundColor Gray
    Write-Host "  Endpoint:  http://<this-machine>:29100/metrics" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Run it manually right now with:" -ForegroundColor Yellow
    Write-Host "  Start-ScheduledTask -TaskName `"$TaskName`"" -ForegroundColor Gray
    Write-Host ""

    exit 0
}
catch {
    Write-Host ""
    Write-Host "===========================================================" -ForegroundColor Red
    Write-Host "  Task Creation Failed" -ForegroundColor Red
    Write-Host "===========================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
