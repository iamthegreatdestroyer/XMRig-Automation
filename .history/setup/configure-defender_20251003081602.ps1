<#
.SYNOPSIS
    Configures Windows Defender exclusions for XMRig.

.DESCRIPTION
    Adds folder and process exclusions to Windows Defender to prevent
    false positive detections of XMRig as malware.

.PARAMETER XMRigPath
    Path to XMRig installation directory.

.EXAMPLE
    .\configure-defender.ps1 -XMRigPath "C:\XMRig"

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
    Requires Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
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
Write-Host "  Windows Defender Configuration" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠ IMPORTANT NOTICE ⚠" -ForegroundColor Yellow
Write-Host ""
Write-Host "XMRig is a legitimate cryptocurrency mining software, but it is" -ForegroundColor Gray
Write-Host "often detected as a 'Potentially Unwanted Program' (PUP) or malware" -ForegroundColor Gray
Write-Host "by antivirus software because the same code is used by malicious actors." -ForegroundColor Gray
Write-Host ""
Write-Host "This script will add exclusions to Windows Defender to prevent" -ForegroundColor Gray
Write-Host "XMRig from being quarantined or deleted." -ForegroundColor Gray
Write-Host ""
Write-Host "Only proceed if:" -ForegroundColor Yellow
Write-Host "  ✓ You downloaded XMRig from the official source (xmrig.com)" -ForegroundColor Gray
Write-Host "  ✓ You trust the files in $XMRigPath" -ForegroundColor Gray
Write-Host "  ✓ You understand the security implications" -ForegroundColor Gray
Write-Host ""

$confirmation = Read-Host "Do you want to proceed? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host ""
    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host ""

try {
    # Add folder exclusion
    Write-Host "[1/3] Adding folder exclusion..." -ForegroundColor Cyan
    Write-Host "  Excluding: $XMRigPath" -ForegroundColor Gray
    
    Add-MpPreference -ExclusionPath $XMRigPath -ErrorAction Stop
    Write-Host "  ✓ Folder exclusion added" -ForegroundColor Green
    Write-Host ""
    
    # Add process exclusion
    Write-Host "[2/3] Adding process exclusion..." -ForegroundColor Cyan
    $xmrigExe = Join-Path $XMRigPath "xmrig.exe"
    Write-Host "  Excluding: $xmrigExe" -ForegroundColor Gray
    
    Add-MpPreference -ExclusionProcess "xmrig.exe" -ErrorAction Stop
    Write-Host "  ✓ Process exclusion added" -ForegroundColor Green
    Write-Host ""
    
    # Verify exclusions
    Write-Host "[3/3] Verifying exclusions..." -ForegroundColor Cyan
    $preferences = Get-MpPreference
    
    $folderExcluded = $preferences.ExclusionPath -contains $XMRigPath
    $processExcluded = $preferences.ExclusionProcess -contains "xmrig.exe"
    
    if ($folderExcluded -and $processExcluded) {
        Write-Host "  ✓ All exclusions verified successfully" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Warning: Could not verify all exclusions" -ForegroundColor Yellow
        if (-not $folderExcluded) {
            Write-Host "    - Folder exclusion not found" -ForegroundColor Yellow
        }
        if (-not $processExcluded) {
            Write-Host "    - Process exclusion not found" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # Success message
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ Windows Defender Configured Successfully!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Exclusions added:" -ForegroundColor White
    Write-Host "  • Folder: $XMRigPath" -ForegroundColor Gray
    Write-Host "  • Process: xmrig.exe" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Note: If you're using other antivirus software, you may need to" -ForegroundColor Yellow
    Write-Host "add similar exclusions manually in their respective settings." -ForegroundColor Yellow
    Write-Host ""
    
    exit 0
    
}
catch {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ Configuration Failed" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual exclusion instructions:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Open Windows Security (Start → Settings → Update & Security → Windows Security)" -ForegroundColor Gray
    Write-Host "2. Click 'Virus & threat protection'" -ForegroundColor Gray
    Write-Host "3. Under 'Virus & threat protection settings', click 'Manage settings'" -ForegroundColor Gray
    Write-Host "4. Scroll down to 'Exclusions' and click 'Add or remove exclusions'" -ForegroundColor Gray
    Write-Host "5. Click 'Add an exclusion' and select 'Folder'" -ForegroundColor Gray
    Write-Host "6. Browse to and select: $XMRigPath" -ForegroundColor Gray
    Write-Host "7. Repeat steps 5-6, but select 'Process' and enter: xmrig.exe" -ForegroundColor Gray
    Write-Host ""
    
    exit 1
}
