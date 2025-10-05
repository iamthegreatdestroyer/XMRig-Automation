<#
.SYNOPSIS
    Creates a Windows scheduled task for XMRig auto-start.

.DESCRIPTION
    Creates a scheduled task that starts XMRig automatically at system boot
    with a 30-second delay. Configures the task to restart on failure and
    run with highest privileges.

.PARAMETER TaskName
    Name for the scheduled task.

.PARAMETER ScriptPath
    Full path to the start-mining.bat script.

.PARAMETER XMRigPath
    Path to XMRig installation directory (working directory).

.EXAMPLE
    .\create-scheduled-task.ps1 -TaskName "XMRig Auto Start" -ScriptPath "C:\XMRig-Automation\scripts\start-mining.bat" -XMRigPath "C:\XMRig"

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
    Requires Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$TaskName,
    
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,
    
    [Parameter(Mandatory=$true)]
    [string]$XMRigPath
)

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges!" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Scheduled Task Configuration" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    # Verify script exists
    Write-Host "[1/5] Verifying script path..." -ForegroundColor Cyan
    if (-not (Test-Path $ScriptPath)) {
        throw "Start mining script not found: $ScriptPath"
    }
    Write-Host "  ✓ Script found: $ScriptPath" -ForegroundColor Green
    Write-Host ""
    
    # Check if task already exists
    Write-Host "[2/5] Checking for existing task..." -ForegroundColor Cyan
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    
    if ($existingTask) {
        Write-Host "  ! Task '$TaskName' already exists" -ForegroundColor Yellow
        $overwrite = Read-Host "  Do you want to overwrite it? (yes/no)"
        
        if ($overwrite -eq "yes") {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "  ✓ Existing task removed" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "Operation cancelled by user." -ForegroundColor Yellow
            Write-Host ""
            exit 0
        }
    } else {
        Write-Host "  ✓ No existing task found" -ForegroundColor Green
    }
    Write-Host ""
    
    # Create task action
    Write-Host "[3/5] Creating task action..." -ForegroundColor Cyan
    $action = New-ScheduledTaskAction `
        -Execute "cmd.exe" `
        -Argument "/c `"$ScriptPath`"" `
        -WorkingDirectory $XMRigPath
    
    Write-Host "  ✓ Action: Start mining script" -ForegroundColor Green
    Write-Host ""
    
    # Create task trigger (at startup with 30 second delay)
    Write-Host "[4/5] Creating task trigger..." -ForegroundColor Cyan
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = "PT30S"  # 30 second delay
    
    Write-Host "  ✓ Trigger: At system startup (30s delay)" -ForegroundColor Green
    Write-Host ""
    
    # Create task settings
    Write-Host "[5/5] Configuring task settings..." -ForegroundColor Cyan
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Days 0)
    
    Write-Host "  ✓ Allow start on batteries: Yes" -ForegroundColor Gray
    Write-Host "  ✓ Don't stop on batteries: Yes" -ForegroundColor Gray
    Write-Host "  ✓ Start when available: Yes" -ForegroundColor Gray
    Write-Host "  ✓ Restart on failure: 999 times (1 min interval)" -ForegroundColor Gray
    Write-Host "  ✓ Execution time limit: Unlimited" -ForegroundColor Gray
    Write-Host ""
    
    # Create task principal (run with highest privileges)
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest
    
    Write-Host "  Creating scheduled task..." -ForegroundColor Cyan
    
    # Register the task
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Automatically starts XMRig Monero mining at system startup with auto-restart on failure" `
        -ErrorAction Stop | Out-Null
    
    Write-Host "  ✓ Task registered successfully" -ForegroundColor Green
    Write-Host ""
    
    # Verify task creation
    Write-Host "Verifying task..." -ForegroundColor Cyan
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    
    if ($task) {
        Write-Host "  ✓ Task verified" -ForegroundColor Green
        Write-Host "  State: $($task.State)" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Success message
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ Scheduled Task Created Successfully!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Task Configuration:" -ForegroundColor White
    Write-Host "  Name:        $TaskName" -ForegroundColor Gray
    Write-Host "  Trigger:     At system startup (30 second delay)" -ForegroundColor Gray
    Write-Host "  Action:      Start mining script" -ForegroundColor Gray
    Write-Host "  Script:      $ScriptPath" -ForegroundColor Gray
    Write-Host "  Privileges:  SYSTEM (Highest)" -ForegroundColor Gray
    Write-Host "  Auto-restart: Yes (on failure)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Mining will automatically start:" -ForegroundColor Yellow
    Write-Host "  • When Windows starts (after 30 second delay)" -ForegroundColor Gray
    Write-Host "  • After crashes (restarts every minute, up to 999 times)" -ForegroundColor Gray
    Write-Host "  • Even if no user is logged in" -ForegroundColor Gray
    Write-Host ""
    
    # Ask to test task
    $test = Read-Host "Would you like to test the task now? (yes/no)"
    if ($test -eq "yes") {
        Write-Host ""
        Write-Host "Starting task..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $TaskName
        
        Start-Sleep -Seconds 3
        
        $running = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
        if ($running) {
            Write-Host "✓ XMRig started successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Check status with: check-status.ps1" -ForegroundColor Gray
        } else {
            Write-Host "⚠ Task started, but XMRig process not detected yet." -ForegroundColor Yellow
            Write-Host "  This is normal - it may take a few seconds to start." -ForegroundColor Gray
            Write-Host "  Check logs with: view-logs.bat" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    Write-Host "You can manage this task in Task Scheduler:" -ForegroundColor White
    Write-Host "  Start → Task Scheduler → Task Scheduler Library → $TaskName" -ForegroundColor Gray
    Write-Host ""
    
    exit 0
    
} catch {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ Task Creation Failed" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual task creation instructions:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Press Win+R and type: taskschd.msc" -ForegroundColor Gray
    Write-Host "2. In Task Scheduler, click 'Create Task' (not 'Create Basic Task')" -ForegroundColor Gray
    Write-Host "3. General tab:" -ForegroundColor Gray
    Write-Host "   - Name: $TaskName" -ForegroundColor Gray
    Write-Host "   - User: SYSTEM" -ForegroundColor Gray
    Write-Host "   - Run with highest privileges: Checked" -ForegroundColor Gray
    Write-Host "   - Run whether user is logged on or not: Checked" -ForegroundColor Gray
    Write-Host "4. Triggers tab:" -ForegroundColor Gray
    Write-Host "   - New → Begin the task: At startup" -ForegroundColor Gray
    Write-Host "   - Delay task for: 30 seconds" -ForegroundColor Gray
    Write-Host "5. Actions tab:" -ForegroundColor Gray
    Write-Host "   - New → Action: Start a program" -ForegroundColor Gray
    Write-Host "   - Program: cmd.exe" -ForegroundColor Gray
    Write-Host "   - Arguments: /c `"$ScriptPath`"" -ForegroundColor Gray
    Write-Host "   - Start in: $XMRigPath" -ForegroundColor Gray
    Write-Host "6. Settings tab:" -ForegroundColor Gray
    Write-Host "   - Allow task to run on batteries: Checked" -ForegroundColor Gray
    Write-Host "   - If the task fails, restart every: 1 minute" -ForegroundColor Gray
    Write-Host "   - Attempt to restart up to: 999 times" -ForegroundColor Gray
    Write-Host "7. Click OK to save" -ForegroundColor Gray
    Write-Host ""
    
    exit 1
}
