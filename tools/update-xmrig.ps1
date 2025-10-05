<#
.SYNOPSIS
    Updates XMRig to the latest version.

.DESCRIPTION
    Checks GitHub for latest XMRig release, downloads if newer version available,
    backs up configuration, installs new version, and restarts mining.

.PARAMETER XMRigPath
    Path to XMRig installation directory.

.EXAMPLE
    .\update-xmrig.ps1
    .\update-xmrig.ps1 -XMRigPath "C:\XMRig"

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
    Requires Administrator privileges
#>

[CmdletBinding()]
param(
    [string]$XMRigPath = "C:\XMRig"
)

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Administrator privileges required!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  XMRig Update Checker" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    # Get current version
    Write-Host "[1/7] Checking current version..." -ForegroundColor Cyan
    $xmrigExe = Join-Path $XMRigPath "xmrig.exe"
    
    if (-not (Test-Path $xmrigExe)) {
        throw "XMRig not found at $XMRigPath"
    }
    
    $currentVersion = & $xmrigExe --version 2>&1 | Select-Object -First 1
    if ($currentVersion -match "XMRig (\d+\.\d+\.\d+)") {
        $currentVersion = $matches[1]
        Write-Host "  Current version: $currentVersion" -ForegroundColor Gray
    }
    else {
        $currentVersion = "unknown"
        Write-Host "  Current version: Unknown" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Check latest version on GitHub
    Write-Host "[2/7] Checking for updates..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    $apiUrl = "https://api.github.com/repos/xmrig/xmrig/releases/latest"
    $release = Invoke-RestMethod -Uri $apiUrl -Method Get
    $latestVersion = $release.tag_name -replace "^v", ""
    
    Write-Host "  Latest version: $latestVersion" -ForegroundColor Gray
    Write-Host ""
    
    # Compare versions
    if ($currentVersion -eq $latestVersion) {
        Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "  ✓ XMRig is already up to date!" -ForegroundColor Green
        Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""
        Write-Host "Current version: $currentVersion" -ForegroundColor White
        Write-Host "No update needed." -ForegroundColor Gray
        Write-Host ""
        exit 0
    }
    
    Write-Host "Update available: $currentVersion → $latestVersion" -ForegroundColor Yellow
    Write-Host ""
    
    $confirm = Read-Host "Do you want to update? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Update cancelled." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
    
    # Backup configuration
    Write-Host "[3/7] Backing up configuration..." -ForegroundColor Cyan
    $backupScript = Join-Path $PSScriptRoot "backup-config.ps1"
    if (Test-Path $backupScript) {
        & $backupScript -XMRigPath $XMRigPath
    }
    else {
        # Manual backup
        $configBackup = Join-Path $env:TEMP "xmrig-config-backup.json"
        Copy-Item (Join-Path $XMRigPath "config.json") -Destination $configBackup
        Write-Host "  ✓ Configuration backed up" -ForegroundColor Green
    }
    Write-Host ""
    
    # Stop mining
    Write-Host "[4/7] Stopping mining..." -ForegroundColor Cyan
    $process = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Name "xmrig" -Force
        Start-Sleep -Seconds 2
        Write-Host "  ✓ Mining stopped" -ForegroundColor Green
    }
    else {
        Write-Host "  Mining was not running" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Download new version
    Write-Host "[5/7] Downloading XMRig $latestVersion..." -ForegroundColor Cyan
    $asset = $release.assets | Where-Object { $_.name -like "*msvc-win64.zip" } | Select-Object -First 1
    
    if (-not $asset) {
        throw "Could not find Windows 64-bit release"
    }
    
    $zipPath = Join-Path $env:TEMP "xmrig-latest.zip"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
    $ProgressPreference = 'Continue'
    
    Write-Host "  ✓ Downloaded $([math]::Round((Get-Item $zipPath).Length / 1MB, 2)) MB" -ForegroundColor Green
    Write-Host ""
    
    # Extract and install
    Write-Host "[6/7] Installing update..." -ForegroundColor Cyan
    $extractPath = Join-Path $env:TEMP "xmrig-extract"
    
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }
    
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    $extractedFolder = Get-ChildItem $extractPath -Directory | Select-Object -First 1
    
    # Copy new files (preserving config)
    $configPath = Join-Path $XMRigPath "config.json"
    $configContent = Get-Content $configPath -Raw
    
    Get-ChildItem $extractedFolder.FullName -File | ForEach-Object {
        if ($_.Name -ne "config.json") {
            Copy-Item $_.FullName -Destination $XMRigPath -Force
        }
    }
    
    # Restore config
    Set-Content -Path $configPath -Value $configContent
    
    Write-Host "  ✓ XMRig updated to $latestVersion" -ForegroundColor Green
    Write-Host ""
    
    # Cleanup
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    
    # Restart mining
    Write-Host "[7/7] Restarting mining..." -ForegroundColor Cyan
    $startScript = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts\start-mining.bat"
    
    if (Test-Path $startScript) {
        Start-Process -FilePath $startScript -WorkingDirectory $XMRigPath
        Start-Sleep -Seconds 3
        
        $process = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Host "  ✓ Mining restarted successfully" -ForegroundColor Green
        }
        else {
            Write-Host "  ⚠ Please start mining manually" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # Success
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ Update Complete!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Updated: $currentVersion → $latestVersion" -ForegroundColor White
    Write-Host "Configuration preserved" -ForegroundColor Gray
    Write-Host "Mining restarted" -ForegroundColor Gray
    Write-Host ""
    
    exit 0
    
}
catch {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ Update Failed" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Configuration backup may be at: $env:TEMP\xmrig-config-backup.json" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
