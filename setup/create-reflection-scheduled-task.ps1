<#
.SYNOPSIS
    Creates a Windows scheduled task for the nightly mining reflection job.

.DESCRIPTION
    Registers a daily task that runs the reflection through the Ollama
    pre-flight guard (setup\ensure-ollama-and-reflect.ps1), which ensures
    `ollama serve` is listening before invoking `python -m intelligence.advisor
    --reflect`. This is a heavy REFLECT-mode job (intelligence/advisor.py) that
    pauses mining, summarizes the day's decision log via a local LLM, and
    resumes.

    Thermal-safe by design: AdmissionController's thermal gate (see
    intelligence/admission.py) will defer the job rather than run it if the
    predicted temperature is too high, and nightly_reflect() is idempotent
    (a no-op if today's reflection already exists). To turn that into a
    working retry mechanism without any custom retry scripting, this task
    uses Task Scheduler's native repetition: it fires once at -AtTime, then
    re-fires every -RetryIntervalMinutes for -RetryWindowHours. Only the
    first non-deferred firing in that window actually writes a reflection;
    every firing after that is a harmless no-op.

    Runs as the current user (not SYSTEM) — the XMRig API token this job
    needs is stored per-user, not accessible to a SYSTEM-context task.

.PARAMETER TaskName
    Name for the scheduled task.

.PARAMETER RepoPath
    Full path to the XMRig-Automation repository (working directory).

.PARAMETER AtTime
    Local time to first attempt the reflection each night. Default 03:00 —
    late enough that mining has had a full day logged, early enough to
    finish well before typical morning use.

.PARAMETER RetryWindowHours
    How many hours to keep retrying if the first attempt is thermally
    deferred. Default 3 (i.e. gives up retrying by ~06:00 if using the
    default -AtTime).

.PARAMETER RetryIntervalMinutes
    How often to retry within the window. Default 30.

.EXAMPLE
    .\create-reflection-scheduled-task.ps1 -RepoPath "C:\Users\sgbil\XMRig-Automation"

.NOTES
    Author: XMRig Automation Project
    Does NOT require Administrator privileges — registers a task for the
    current user only.
#>

[CmdletBinding()]
param(
    [string]$TaskName = "XMRig Nightly Reflection",

    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [string]$AtTime = "03:00",

    [int]$RetryWindowHours = 3,

    [int]$RetryIntervalMinutes = 30
)

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Nightly Reflection — Scheduled Task Configuration" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "[1/5] Verifying repository path..." -ForegroundColor Cyan
    $advisorModule = Join-Path $RepoPath "intelligence\advisor.py"
    if (-not (Test-Path $advisorModule)) {
        throw "intelligence/advisor.py not found under: $RepoPath"
    }
    Write-Host "  Found: $advisorModule" -ForegroundColor Green
    Write-Host ""

    Write-Host "[2/5] Checking for existing task..." -ForegroundColor Cyan
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "  Task '$TaskName' already exists — removing to re-register." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    else {
        Write-Host "  No existing task found." -ForegroundColor Green
    }
    Write-Host ""

    Write-Host "[3/5] Creating task action..." -ForegroundColor Cyan
    # Run through the Ollama pre-flight guard rather than invoking python
    # directly: it ensures `ollama serve` is actually listening before the
    # reflection runs, so an auto-updated / rebooted / slept Ollama can no
    # longer silently turn every nightly reflection into an empty stub
    # (as happened for 12 straight nights, 2026-07-10..21).
    $wrapper = Join-Path $RepoPath "setup\ensure-ollama-and-reflect.ps1"
    if (-not (Test-Path $wrapper)) {
        throw "Pre-flight guard not found: $wrapper"
    }
    $psExe = (Get-Command powershell.exe).Source
    $wrapperArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$wrapper`" -RepoPath `"$RepoPath`""
    $action = New-ScheduledTaskAction `
        -Execute $psExe `
        -Argument $wrapperArgs `
        -WorkingDirectory $RepoPath
    Write-Host "  Action: powershell -File setup\ensure-ollama-and-reflect.ps1 (guarded reflection)" -ForegroundColor Green
    Write-Host ""

    Write-Host "[4/5] Creating task trigger..." -ForegroundColor Cyan
    $trigger = New-ScheduledTaskTrigger -Daily -At $AtTime
    $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At $AtTime `
        -RepetitionInterval (New-TimeSpan -Minutes $RetryIntervalMinutes) `
        -RepetitionDuration (New-TimeSpan -Hours $RetryWindowHours)).Repetition
    Write-Host "  Trigger: daily at $AtTime, retry every ${RetryIntervalMinutes}m for ${RetryWindowHours}h if deferred" -ForegroundColor Green
    Write-Host ""

    Write-Host "[5/5] Configuring task settings and principal..." -ForegroundColor Cyan
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    # Runs as the current user, in their interactive session — NOT SYSTEM,
    # since the XMRig API token is stored per-user. Interactive (rather
    # than S4U/"run whether logged on or not") is deliberate: this is a
    # personal laptop that stays logged in (locked, not logged out)
    # overnight, and Interactive registers without needing admin rights,
    # unlike S4U which requires elevation to grant unattended-logon trust.
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
        -Description "Nightly LLM-generated mining reflection (Local Intelligence Layer). Thermally deferred jobs retry automatically within the configured window." `
        -ErrorAction Stop | Out-Null

    Write-Host "  Task registered for user: $currentUser" -ForegroundColor Green
    Write-Host ""

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Scheduled Task Created Successfully" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Name:      $TaskName" -ForegroundColor Gray
    Write-Host "  State:     $($task.State)" -ForegroundColor Gray
    Write-Host "  Schedule:  Daily at $AtTime (retries every ${RetryIntervalMinutes}m up to ${RetryWindowHours}h)" -ForegroundColor Gray
    Write-Host "  Output:    logs\reflections\YYYY-MM-DD.md" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Run it manually right now with:" -ForegroundColor Yellow
    Write-Host "  Start-ScheduledTask -TaskName `"$TaskName`"" -ForegroundColor Gray
    Write-Host ""

    exit 0
}
catch {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  Task Creation Failed" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
