<#
.SYNOPSIS
    Backs up XMRig configuration and related files.

.DESCRIPTION
    Creates timestamped backup of config.json, custom scripts, and log files.
    Maintains last 10 backups and automatically deletes older ones.

.PARAMETER BackupPath
    Directory to store backups (default: .\backups)

.EXAMPLE
    .\backup-config.ps1
    .\backup-config.ps1 -BackupPath "D:\Backups"

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
#>

param(
    [string]$BackupPath = (Join-Path $PSScriptRoot "..\backups"),
    [string]$XMRigPath = "C:\XMRig"
)

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  XMRig Configuration Backup" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    # Create backup directory
    if (-not (Test-Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-Host "Created backup directory: $BackupPath" -ForegroundColor Gray
    }
    
    # Generate timestamp
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupName = "xmrig-backup-$timestamp"
    $backupFolder = Join-Path $BackupPath $backupName
    
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
    
    Write-Host "Creating backup: $backupName" -ForegroundColor Cyan
    Write-Host ""
    
    # Backup config.json
    Write-Host "[1/4] Backing up configuration..." -ForegroundColor Cyan
    $configSource = Join-Path $XMRigPath "config.json"
    if (Test-Path $configSource) {
        Copy-Item $configSource -Destination (Join-Path $backupFolder "config.json")
        Write-Host "  ✓ config.json backed up" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ config.json not found" -ForegroundColor Yellow
    }
    
    # Backup log files
    Write-Host "[2/4] Backing up log files..." -ForegroundColor Cyan
    $logFiles = @("xmrig.log")
    $logsBackup = Join-Path $backupFolder "logs"
    New-Item -ItemType Directory -Path $logsBackup -Force | Out-Null
    
    foreach ($log in $logFiles) {
        $logPath = Join-Path $XMRigPath $log
        if (Test-Path $logPath) {
            Copy-Item $logPath -Destination (Join-Path $logsBackup $log)
            Write-Host "  ✓ $log backed up" -ForegroundColor Green
        }
    }
    
    # Backup restart log if exists
    $restartLog = Join-Path $XMRigPath "logs\restart-log.txt"
    if (Test-Path $restartLog) {
        Copy-Item $restartLog -Destination (Join-Path $logsBackup "restart-log.txt")
        Write-Host "  ✓ restart-log.txt backed up" -ForegroundColor Green
    }
    
    # Backup custom scripts if modified
    Write-Host "[3/4] Backing up custom scripts..." -ForegroundColor Cyan
    $scriptsBackup = Join-Path $backupFolder "scripts"
    $automationPath = Split-Path $PSScriptRoot -Parent
    $scriptsSource = Join-Path $automationPath "scripts"
    
    if (Test-Path $scriptsSource) {
        Copy-Item $scriptsSource -Destination $scriptsBackup -Recurse
        Write-Host "  ✓ Scripts backed up" -ForegroundColor Green
    }
    
    # Create info file
    Write-Host "[4/4] Creating backup info..." -ForegroundColor Cyan
    $infoFile = Join-Path $backupFolder "backup-info.txt"
    $info = @"
XMRig Configuration Backup
==========================
Backup Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
XMRig Path: $XMRigPath
Automation Path: $automationPath

Contents:
- config.json
- Log files
- Custom scripts

To restore:
1. Stop mining
2. Copy config.json to $XMRigPath
3. Start mining
"@
    
    Set-Content -Path $infoFile -Value $info
    Write-Host "  ✓ Backup info created" -ForegroundColor Green
    Write-Host ""
    
    # Compress to ZIP
    Write-Host "Compressing backup..." -ForegroundColor Cyan
    $zipPath = "$backupFolder.zip"
    Compress-Archive -Path $backupFolder -DestinationPath $zipPath -Force
    Remove-Item $backupFolder -Recurse -Force
    
    $zipSize = (Get-Item $zipPath).Length / 1KB
    Write-Host "  ✓ Backup compressed ($([math]::Round($zipSize, 2)) KB)" -ForegroundColor Green
    Write-Host ""
    
    # Clean old backups (keep last 10)
    Write-Host "Cleaning old backups..." -ForegroundColor Cyan
    $allBackups = Get-ChildItem $BackupPath -Filter "xmrig-backup-*.zip" | Sort-Object CreationTime -Descending
    
    if ($allBackups.Count -gt 10) {
        $toDelete = $allBackups | Select-Object -Skip 10
        foreach ($old in $toDelete) {
            Remove-Item $old.FullName -Force
            Write-Host "  Deleted old backup: $($old.Name)" -ForegroundColor Gray
        }
        Write-Host "  ✓ Kept last 10 backups" -ForegroundColor Green
    }
    else {
        Write-Host "  ✓ ${($allBackups.Count)} backups total (under limit)" -ForegroundColor Green
    }
    Write-Host ""
    
    # Success
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ Backup Complete!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Backup saved to: $zipPath" -ForegroundColor White
    Write-Host "Backup size: $([math]::Round($zipSize, 2)) KB" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To restore this backup:" -ForegroundColor Yellow
    Write-Host "1. Extract $backupName.zip" -ForegroundColor Gray
    Write-Host "2. Stop mining" -ForegroundColor Gray
    Write-Host "3. Copy config.json to $XMRigPath" -ForegroundColor Gray
    Write-Host "4. Start mining" -ForegroundColor Gray
    Write-Host ""
    
    exit 0
    
}
catch {
    Write-Host ""
    Write-Host "Error creating backup: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
