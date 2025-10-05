<#
.SYNOPSIS
    Installs XMRig miner to specified directory.

.DESCRIPTION
    Downloads the latest XMRig release from GitHub, extracts it to the specified
    directory, and copies the configuration file.

.PARAMETER InstallPath
    Target installation directory for XMRig.

.PARAMETER ConfigPath
    Path to the configuration file to copy.

.EXAMPLE
    .\install.ps1 -InstallPath "C:\XMRig" -ConfigPath ".\config\config.json"

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
    Requires Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
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
Write-Host "  XMRig Installation Script" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    # Create installation directory
    Write-Host "[1/6] Creating installation directory..." -ForegroundColor Cyan
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        Write-Host "  ✓ Created: $InstallPath" -ForegroundColor Green
    }
    else {
        Write-Host "  ✓ Directory already exists: $InstallPath" -ForegroundColor Green
    }
    Write-Host ""
    
    # Download latest XMRig
    Write-Host "[2/6] Downloading latest XMRig release..." -ForegroundColor Cyan
    $apiUrl = "https://api.github.com/repos/xmrig/xmrig/releases/latest"
    
    # Set TLS 1.2 for GitHub API
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    Write-Host "  Fetching release information..." -ForegroundColor Gray
    $release = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
    $version = $release.tag_name
    Write-Host "  Latest version: $version" -ForegroundColor Gray
    
    # Find Windows 64-bit asset
    $asset = $release.assets | Where-Object { $_.name -like "*msvc-win64.zip" } | Select-Object -First 1
    
    if (-not $asset) {
        throw "Could not find Windows 64-bit release asset"
    }
    
    $downloadUrl = $asset.browser_download_url
    $zipPath = Join-Path $env:TEMP "xmrig-latest.zip"
    
    Write-Host "  Downloading from: $downloadUrl" -ForegroundColor Gray
    Write-Host "  This may take a few minutes..." -ForegroundColor Yellow
    
    # Download with progress
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -ErrorAction Stop
    $ProgressPreference = 'Continue'
    
    Write-Host "  ✓ Downloaded: $(([math]::Round((Get-Item $zipPath).Length / 1MB, 2))) MB" -ForegroundColor Green
    Write-Host ""
    
    # Extract archive
    Write-Host "[3/6] Extracting XMRig..." -ForegroundColor Cyan
    $extractPath = Join-Path $env:TEMP "xmrig-extract"
    
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }
    
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    Write-Host "  ✓ Extracted to temporary location" -ForegroundColor Green
    
    # Find extracted folder
    $extractedFolder = Get-ChildItem $extractPath -Directory | Select-Object -First 1
    
    if (-not $extractedFolder) {
        throw "Could not find extracted XMRig folder"
    }
    
    # Copy files to installation directory
    Write-Host "  Copying files to $InstallPath..." -ForegroundColor Gray
    Get-ChildItem $extractedFolder.FullName -Recurse | ForEach-Object {
        $target = Join-Path $InstallPath $_.FullName.Substring($extractedFolder.FullName.Length)
        if ($_.PSIsContainer) {
            if (-not (Test-Path $target)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }
        }
        else {
            Copy-Item $_.FullName -Destination $target -Force
        }
    }
    
    Write-Host "  ✓ XMRig copied to installation directory" -ForegroundColor Green
    Write-Host ""
    
    # Copy configuration
    Write-Host "[4/6] Installing configuration..." -ForegroundColor Cyan
    if (Test-Path $ConfigPath) {
        $configDest = Join-Path $InstallPath "config.json"
        Copy-Item $ConfigPath -Destination $configDest -Force
        Write-Host "  ✓ Configuration installed" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Configuration file not found: $ConfigPath" -ForegroundColor Yellow
        Write-Host "  You'll need to configure XMRig manually" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Create logs directory
    Write-Host "[5/6] Creating logs directory..." -ForegroundColor Cyan
    $logsPath = Join-Path $InstallPath "logs"
    if (-not (Test-Path $logsPath)) {
        New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    }
    Write-Host "  ✓ Logs directory created" -ForegroundColor Green
    Write-Host ""
    
    # Verify installation
    Write-Host "[6/6] Verifying installation..." -ForegroundColor Cyan
    $xmrigExe = Join-Path $InstallPath "xmrig.exe"
    if (Test-Path $xmrigExe) {
        $fileInfo = Get-Item $xmrigExe
        Write-Host "  ✓ xmrig.exe found ($([math]::Round($fileInfo.Length / 1MB, 2)) MB)" -ForegroundColor Green
        Write-Host "  ✓ Version: $version" -ForegroundColor Green
    }
    else {
        throw "xmrig.exe not found after installation"
    }
    Write-Host ""
    
    # Cleanup
    Write-Host "Cleaning up temporary files..." -ForegroundColor Gray
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }
    Write-Host "  ✓ Cleanup complete" -ForegroundColor Green
    Write-Host ""
    
    # Success message
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ XMRig Installation Successful!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Installation Path: $InstallPath" -ForegroundColor White
    Write-Host "  Version: $version" -ForegroundColor White
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Configure Windows Defender exclusions" -ForegroundColor Gray
    Write-Host "  2. Enable huge pages" -ForegroundColor Gray
    Write-Host "  3. Create scheduled task for auto-start" -ForegroundColor Gray
    Write-Host ""
    
    exit 0
    
}
catch {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ Installation Failed" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please try the following:" -ForegroundColor Yellow
    Write-Host "  1. Check your internet connection" -ForegroundColor Gray
    Write-Host "  2. Ensure you have Administrator privileges" -ForegroundColor Gray
    Write-Host "  3. Verify GitHub is accessible (https://github.com)" -ForegroundColor Gray
    Write-Host "  4. Try downloading XMRig manually from https://xmrig.com" -ForegroundColor Gray
    Write-Host ""
    
    # Cleanup on failure
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    exit 1
}
