<#
.SYNOPSIS
    Configures huge pages for XMRig performance optimization.

.DESCRIPTION
    Enables huge pages (large pages) support in Windows to improve XMRig
    hashrate by 10-20%. Grants the "Lock pages in memory" privilege to the
    current user account.

.EXAMPLE
    .\configure-hugepages.ps1

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
    Requires Administrator privileges
    System restart required after configuration
#>

[CmdletBinding()]
param()

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges!" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Huge Pages Configuration" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "What are Huge Pages?" -ForegroundColor Yellow
Write-Host ""
Write-Host "Huge pages (also called large pages) allow XMRig to allocate" -ForegroundColor Gray
Write-Host "memory more efficiently, resulting in:" -ForegroundColor Gray
Write-Host "  • 10-20% hashrate improvement" -ForegroundColor Green
Write-Host "  • Lower CPU cache misses" -ForegroundColor Green
Write-Host "  • Better RandomX performance" -ForegroundColor Green
Write-Host ""
Write-Host "This script will grant your user account the 'Lock pages in memory'" -ForegroundColor Gray
Write-Host "privilege, which is required for huge pages support." -ForegroundColor Gray
Write-Host ""
Write-Host "⚠ A system restart is required after configuration" -ForegroundColor Yellow
Write-Host ""

try {
    # Get current user
    Write-Host "[1/4] Getting user information..." -ForegroundColor Cyan
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Host "  Current user: $currentUser" -ForegroundColor Gray
    Write-Host ""
    
    # Export current security policy
    Write-Host "[2/4] Exporting current security policy..." -ForegroundColor Cyan
    $tempFile = Join-Path $env:TEMP "secpol.cfg"
    $tempFileOut = Join-Path $env:TEMP "secpol_new.cfg"
    
    secedit /export /cfg $tempFile /quiet
    
    if (-not (Test-Path $tempFile)) {
        throw "Failed to export security policy"
    }
    
    Write-Host "  ✓ Security policy exported" -ForegroundColor Green
    Write-Host ""
    
    # Modify security policy
    Write-Host "[3/4] Modifying security policy..." -ForegroundColor Cyan
    $policyContent = Get-Content $tempFile
    $lockPagesPrivilege = "SeLockMemoryPrivilege"
    $modified = $false
    
    $newContent = foreach ($line in $policyContent) {
        if ($line -match "^$lockPagesPrivilege\s*=\s*(.*)") {
            # Privilege exists, add user if not already present
            $existingUsers = $matches[1].Trim()
            
            if ($existingUsers -notlike "*$currentUser*") {
                if ($existingUsers) {
                    "$lockPagesPrivilege = $existingUsers,*$currentUser"
                } else {
                    "$lockPagesPrivilege = *$currentUser"
                }
                $modified = $true
                Write-Host "  Added user to existing privilege" -ForegroundColor Gray
            } else {
                Write-Host "  User already has privilege" -ForegroundColor Yellow
                $line
            }
        } elseif ($line -match "^\[Privilege Rights\]") {
            # Found privilege section, will add after if needed
            $line
            $privilegeFound = $true
        } else {
            $line
        }
    }
    
    # If privilege line doesn't exist, add it
    if (-not $modified -and -not ($policyContent -match "^$lockPagesPrivilege")) {
        Write-Host "  Creating new privilege entry" -ForegroundColor Gray
        $insertIndex = 0
        for ($i = 0; $i -lt $newContent.Count; $i++) {
            if ($newContent[$i] -match "^\[Privilege Rights\]") {
                $insertIndex = $i + 1
                break
            }
        }
        
        if ($insertIndex -gt 0) {
            $newContent = $newContent[0..($insertIndex-1)] + "$lockPagesPrivilege = *$currentUser" + $newContent[$insertIndex..($newContent.Count-1)]
            $modified = $true
        }
    }
    
    if ($modified) {
        $newContent | Set-Content $tempFileOut -Force
        Write-Host "  ✓ Security policy modified" -ForegroundColor Green
    } else {
        Write-Host "  ! No changes needed - privilege already configured" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "  ✓ Huge Pages Already Configured!" -ForegroundColor Green
        Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""
        Write-Host "Your account already has the 'Lock pages in memory' privilege." -ForegroundColor White
        Write-Host ""
        Write-Host "If XMRig is not using huge pages:" -ForegroundColor Yellow
        Write-Host "  1. Ensure you've restarted since the privilege was granted" -ForegroundColor Gray
        Write-Host "  2. Check config.json has 'huge-pages': true" -ForegroundColor Gray
        Write-Host "  3. Look for 'READY (huge pages 100%)' in XMRig output" -ForegroundColor Gray
        Write-Host ""
        
        # Cleanup
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        exit 0
    }
    Write-Host ""
    
    # Import modified policy
    Write-Host "[4/4] Applying new security policy..." -ForegroundColor Cyan
    secedit /configure /db secedit.sdb /cfg $tempFileOut /quiet
    
    # Wait a moment for policy to apply
    Start-Sleep -Seconds 2
    
    Write-Host "  ✓ Security policy applied" -ForegroundColor Green
    Write-Host ""
    
    # Cleanup temporary files
    if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    if (Test-Path $tempFileOut) { Remove-Item $tempFileOut -Force }
    if (Test-Path "secedit.sdb") { Remove-Item "secedit.sdb" -Force }
    
    # Success message
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ Huge Pages Configured Successfully!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Configuration complete:" -ForegroundColor White
    Write-Host "  • User: $currentUser" -ForegroundColor Gray
    Write-Host "  • Privilege: Lock pages in memory" -ForegroundColor Gray
    Write-Host "  • Expected improvement: 10-20% hashrate" -ForegroundColor Green
    Write-Host ""
    Write-Host "⚠ IMPORTANT: You must restart your computer for the changes" -ForegroundColor Yellow
    Write-Host "  to take effect. XMRig will not use huge pages until restart." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "After restart, check XMRig output for:" -ForegroundColor White
    Write-Host "  'READY (huge pages 100%)' - Indicates huge pages are working" -ForegroundColor Green
    Write-Host ""
    
    # Ask about restart
    $restart = Read-Host "Would you like to restart now? (yes/no)"
    if ($restart -eq "yes") {
        Write-Host ""
        Write-Host "Restarting computer in 10 seconds..." -ForegroundColor Yellow
        Write-Host "Press Ctrl+C to cancel" -ForegroundColor Gray
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    } else {
        Write-Host ""
        Write-Host "Please restart your computer manually when convenient." -ForegroundColor Yellow
        Write-Host ""
    }
    
    exit 0
    
} catch {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ Configuration Failed" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual configuration instructions:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Press Win+R and type: gpedit.msc" -ForegroundColor Gray
    Write-Host "2. Navigate to: Computer Configuration → Windows Settings" -ForegroundColor Gray
    Write-Host "   → Security Settings → Local Policies → User Rights Assignment" -ForegroundColor Gray
    Write-Host "3. Double-click 'Lock pages in memory'" -ForegroundColor Gray
    Write-Host "4. Click 'Add User or Group'" -ForegroundColor Gray
    Write-Host "5. Enter your username: $currentUser" -ForegroundColor Gray
    Write-Host "6. Click OK and restart your computer" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Note: Home editions of Windows don't have gpedit.msc." -ForegroundColor Yellow
    Write-Host "XMRig will still work without huge pages, just with lower hashrate." -ForegroundColor Yellow
    Write-Host ""
    
    # Cleanup
    if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tempFileOut) { Remove-Item $tempFileOut -Force -ErrorAction SilentlyContinue }
    
    exit 1
}
