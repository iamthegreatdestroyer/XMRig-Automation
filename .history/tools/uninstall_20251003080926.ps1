<#
.SYNOPSIS
    Uninstalls XMRig and removes all automation components.

.DESCRIPTION
    Performs a clean uninstall by stopping mining, removing scheduled tasks,
    removing Windows Defender exclusions, deleting XMRig directory, and
    removing desktop shortcuts.

.PARAMETER KeepConfig
    Keep configuration backup before uninstalling.

.EXAMPLE
    .\uninstall.ps1
    .\uninstall.ps1 -KeepConfig

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
    Requires Administrator privileges
#>

[CmdletBinding()]
param(
    [switch]$KeepConfig,
    [string]$XMRigPath = "C:\XMRig"
)

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Administrator privileges required!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
Write-Host "  XMRig Uninstaller" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
Write-Host ""
Write-Host "⚠ WARNING: This will completely remove XMRig and all automation!" -ForegroundColor Yellow
Write-Host ""
Write-Host "This will:" -ForegroundColor White
Write-Host "  • Stop mining immediately" -ForegroundColor Gray
Write-Host "  • Remove scheduled auto-start task" -ForegroundColor Gray
Write-Host "  • Remove Windows Defender exclusions" -ForegroundColor Gray
Write-Host "  • Delete XMRig directory: $XMRigPath" -ForegroundColor Gray
Write-Host "  • Remove desktop shortcuts" -ForegroundColor Gray
Write-Host ""

$confirm = Read-Host "Are you sure you want to uninstall? (type 'yes' to confirm)"
if ($confirm -ne "yes") {
    Write-Host ""
    Write-Host "Uninstall cancelled." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host ""

try {
    # Backup configuration if requested
    if ($KeepConfig) {
        Write-Host "[1/6] Creating configuration backup..." -ForegroundColor Cyan
        $backupScript = Join-Path $PSScriptRoot "backup-config.ps1"
        if (Test-Path $backupScript) {
            & $backupScript -XMRigPath $XMRigPath
        }
        Write-Host ""
    }
    
    # Stop mining process
    Write-Host "[1/6] Stopping mining..." -ForegroundColor Cyan
    $process = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Name "xmrig" -Force
        Start-Sleep -Seconds 2
        Write-Host "  ✓ Mining stopped" -ForegroundColor Green
    } else {
        Write-Host "  Mining was not running" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Remove scheduled task
    Write-Host "[2/6] Removing scheduled task..." -ForegroundColor Cyan
    $task = Get-ScheduledTask -TaskName "XMRig Auto Start" -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName "XMRig Auto Start" -Confirm:$false
        Write-Host "  ✓ Scheduled task removed" -ForegroundColor Green
    } else {
        Write-Host "  No scheduled task found" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Remove Windows Defender exclusions
    Write-Host "[3/6] Removing Windows Defender exclusions..." -ForegroundColor Cyan
    try {
        Remove-MpPreference -ExclusionPath $XMRigPath -ErrorAction SilentlyContinue
        Remove-MpPreference -ExclusionProcess "xmrig.exe" -ErrorAction SilentlyContinue
        Write-Host "  ✓ Defender exclusions removed" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠ Could not remove exclusions (may require manual removal)" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Remove desktop shortcuts
    Write-Host "[4/6] Removing desktop shortcuts..." -ForegroundColor Cyan
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcuts = @(
        "XMRig - Start Mining.lnk",
        "XMRig - Stop Mining.lnk",
        "XMRig - Check Status.lnk",
        "XMRig - View Logs.lnk",
        "XMRig - Monitor Performance.lnk",
        "XMRig - Pool Dashboard.url"
    )
    
    $removed = 0
    foreach ($shortcut in $shortcuts) {
        $path = Join-Path $desktop $shortcut
        if (Test-Path $path) {
            Remove-Item $path -Force
            $removed++
        }
    }
    
    if ($removed -gt 0) {
        Write-Host "  ✓ Removed $removed desktop shortcuts" -ForegroundColor Green
    } else {
        Write-Host "  No shortcuts found" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Optional: Revert huge pages (ask user)
    Write-Host "[5/6] Huge pages configuration..." -ForegroundColor Cyan
    Write-Host "  Do you want to remove 'Lock pages in memory' privilege?" -ForegroundColor Yellow
    Write-Host "  (Only affects mining, safe to keep if you might mine again)" -ForegroundColor Gray
    $revertHugePages = Read-Host "  Remove privilege? (yes/no)"
    
    if ($revertHugePages -eq "yes") {
        Write-Host "  Manual removal required:" -ForegroundColor Yellow
        Write-Host "  1. Win + R → gpedit.msc" -ForegroundColor Gray
        Write-Host "  2. Computer Configuration → Windows Settings → Security Settings" -ForegroundColor Gray
        Write-Host "  3. Local Policies → User Rights Assignment" -ForegroundColor Gray
        Write-Host "  4. 'Lock pages in memory' → Remove your user" -ForegroundColor Gray
    } else {
        Write-Host "  Huge pages privilege kept" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Delete XMRig directory
    Write-Host "[6/6] Deleting XMRig directory..." -ForegroundColor Cyan
    if (Test-Path $XMRigPath) {
        $deleteConfirm = Read-Host "  Delete $XMRigPath? (yes/no)"
        if ($deleteConfirm -eq "yes") {
            Remove-Item $XMRigPath -Recurse -Force
            Write-Host "  ✓ XMRig directory deleted" -ForegroundColor Green
        } else {
            Write-Host "  Directory kept at: $XMRigPath" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Directory not found" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Success message
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ Uninstall Complete!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "XMRig has been removed from your system." -ForegroundColor White
    Write-Host ""
    
    if ($KeepConfig) {
        Write-Host "Configuration backup saved (check backups folder)" -ForegroundColor Cyan
        Write-Host ""
    }
    
    Write-Host "You can safely delete the XMRig-Automation folder if desired." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Thank you for using XMRig Automation!" -ForegroundColor Cyan
    Write-Host ""
    
    exit 0
    
} catch {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ Uninstall Failed" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual cleanup may be required:" -ForegroundColor Yellow
    Write-Host "  1. Stop xmrig.exe in Task Manager" -ForegroundColor Gray
    Write-Host "  2. Delete scheduled task 'XMRig Auto Start'" -ForegroundColor Gray
    Write-Host "  3. Delete folder: $XMRigPath" -ForegroundColor Gray
    Write-Host ""
    exit 1
}
