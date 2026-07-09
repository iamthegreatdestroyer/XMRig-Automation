<#
.SYNOPSIS
    Creates a Windows scheduled task for syncing nightly reflections to
    Ryzanstein/Qdrant on the Debian box (Sprint 4.1, Sigma ecosystem
    federation).

.DESCRIPTION
    Registers a daily task that runs `python -m intelligence.ryzanstein_sync`.
    This is a SEPARATE task from "XMRig Nightly Reflection" -- it does not
    modify that task or its schedule in any way. It runs later in the same
    night's retry window so it has the best chance of finding a reflection
    the other task has already written, and is itself idempotent (a
    marker file tracks which reflections have already been synced), so
    firing it more than once, or before a reflection exists yet, is a
    harmless no-op.

    Ryzanstein and Qdrant are both deliberately loopback-only on the Debian
    box for security. This task's script never talks to them directly --
    it scp's the reflection file over SSH and triggers a remote ingest
    script that uses the box's own localhost access.

.PARAMETER TaskName
    Name for the scheduled task.

.PARAMETER RepoPath
    Full path to the XMRig-Automation repository (working directory).

.PARAMETER AtTime
    Local time to first attempt the sync each night. Default 03:30 -- 30
    minutes after the nightly reflection's own first attempt (03:00),
    giving it time to complete before the sync looks for it.

.PARAMETER RetryWindowHours
    How many hours to keep retrying. Default 3, matching the reflection
    task's own retry window (so a late/deferred reflection still gets
    synced once it eventually lands).

.PARAMETER RetryIntervalMinutes
    How often to retry within the window. Default 30.

.EXAMPLE
    .\create-ryzanstein-sync-scheduled-task.ps1 -RepoPath "C:\Users\sgbil\XMRig-Automation"

.NOTES
    Author: XMRig Automation Project
    Does NOT require Administrator privileges -- registers a task for the
    current user only.
#>

[CmdletBinding()]
param(
    [string]$TaskName = "XMRig Ryzanstein Sync",

    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [string]$AtTime = "03:30",

    [int]$RetryWindowHours = 3,

    [int]$RetryIntervalMinutes = 30
)

Write-Host ""
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "  Ryzanstein Sync -- Scheduled Task Configuration" -ForegroundColor White
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "[1/5] Verifying repository path..." -ForegroundColor Cyan
    $syncModule = Join-Path $RepoPath "intelligence\ryzanstein_sync.py"
    if (-not (Test-Path $syncModule)) {
        throw "intelligence/ryzanstein_sync.py not found under: $RepoPath"
    }
    Write-Host "  Found: $syncModule" -ForegroundColor Green
    Write-Host ""

    Write-Host "[2/5] Checking for existing task..." -ForegroundColor Cyan
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "  Task '$TaskName' already exists -- removing to re-register." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    else {
        Write-Host "  No existing task found." -ForegroundColor Green
    }
    Write-Host ""

    Write-Host "[3/5] Creating task action..." -ForegroundColor Cyan
    $pythonExe = (Get-Command python).Source
    $action = New-ScheduledTaskAction `
        -Execute $pythonExe `
        -Argument "-m intelligence.ryzanstein_sync" `
        -WorkingDirectory $RepoPath
    Write-Host "  Action: $pythonExe -m intelligence.ryzanstein_sync" -ForegroundColor Green
    Write-Host ""

    Write-Host "[4/5] Creating task trigger..." -ForegroundColor Cyan
    $trigger = New-ScheduledTaskTrigger -Daily -At $AtTime
    $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At $AtTime `
        -RepetitionInterval (New-TimeSpan -Minutes $RetryIntervalMinutes) `
        -RepetitionDuration (New-TimeSpan -Hours $RetryWindowHours)).Repetition
    Write-Host "  Trigger: daily at $AtTime, retry every ${RetryIntervalMinutes}m for ${RetryWindowHours}h" -ForegroundColor Green
    Write-Host ""

    Write-Host "[5/5] Configuring task settings and principal..." -ForegroundColor Cyan
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    # Same principal choice as the reflection task, for the same reason:
    # this needs the current user's own SSH config/keys (the sigma-box
    # alias lives under this user's profile), so it runs as this user,
    # Interactive logon (no admin rights needed), not SYSTEM/S4U.
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
        -Description "Syncs written nightly reflections to Ryzanstein/Qdrant on the Sigma ecosystem's Debian box for semantic retrieval (Sprint 4.1). Independent of the nightly reflection task -- never modifies it." `
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
    Write-Host "  Schedule:  Daily at $AtTime (retries every ${RetryIntervalMinutes}m up to ${RetryWindowHours}h)" -ForegroundColor Gray
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
