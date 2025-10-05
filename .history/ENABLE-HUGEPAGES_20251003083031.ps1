#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enable Huge Pages for XMRig by granting "Lock pages in memory" privilege.

.DESCRIPTION
    This script grants the current user the "Lock pages in memory" privilege which is required
    for XMRig to use huge pages. This can improve mining performance by 10-20%.
    
    After running this script, you MUST restart your computer for the changes to take effect.

.EXAMPLE
    .\ENABLE-HUGEPAGES.ps1
    
.NOTES
    - Requires Administrator privileges
    - Requires system restart after running
    - Check XMRig log for "huge pages 100%" after restart
#>

[CmdletBinding()]
param()

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   XMRig Huge Pages Enabler" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get current user info
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$userName = $currentUser.Name
$userSid = $currentUser.User.Value

Write-Host "Current User: $userName" -ForegroundColor Yellow
Write-Host "User SID: $userSid`n" -ForegroundColor Yellow

try {
    Write-Host "[1/3] Exporting current security policy..." -ForegroundColor Cyan
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $exitCode = (Start-Process -FilePath "secedit.exe" -ArgumentList "/export","/cfg",$tempFile -Wait -NoNewWindow -PassThru).ExitCode
    
    if ($exitCode -ne 0 -or !(Test-Path $tempFile)) {
        throw "Failed to export security policy. Exit code: $exitCode"
    }
    
    Write-Host "    ✓ Policy exported successfully" -ForegroundColor Green
    
    Write-Host "`n[2/3] Adding Lock pages in memory privilege..." -ForegroundColor Cyan
    
    # Read the exported policy
    $policyContent = Get-Content $tempFile
    
    # Find and modify the SeLockMemoryPrivilege line
    $modified = $false
    $newContent = $policyContent | ForEach-Object {
        if ($_ -match '^SeLockMemoryPrivilege\s*=\s*(.*)$') {
            $existingUsers = $Matches[1].Trim()
            
            # Check if user is already added
            if ($existingUsers -match $userSid) {
                Write-Host "    ℹ User already has Lock pages in memory privilege" -ForegroundColor Yellow
                $_
            }
            elseif ($existingUsers -eq "" -or $existingUsers -eq "*S-1-5-32-544") {
                # Empty or just Administrators group
                $modified = $true
                "SeLockMemoryPrivilege = $existingUsers,*$userSid"
            }
            else {
                # Add to existing list
                $modified = $true
                "SeLockMemoryPrivilege = $existingUsers,*$userSid"
            }
        }
        else {
            $_
        }
    }
    
    if (-not $modified) {
        Write-Host "    ℹ Privilege was already configured" -ForegroundColor Yellow
    }
    else {
        # Save modified content
        $newContent | Set-Content $tempFile -Encoding Unicode
        
        Write-Host "`n[3/3] Applying updated security policy..." -ForegroundColor Cyan
        
        # Apply the modified policy
        $dbFile = [System.IO.Path]::GetTempFileName()
        $exitCode = (Start-Process -FilePath "secedit.exe" -ArgumentList "/configure","/db",$dbFile,"/cfg",$tempFile,"/quiet" -Wait -NoNewWindow -PassThru).ExitCode
        
        if ($exitCode -ne 0) {
            throw "Failed to apply security policy. Exit code: $exitCode"
        }
        
        # Clean up database file
        if (Test-Path $dbFile) {
            Remove-Item $dbFile -Force
        }
        
        Write-Host "    ✓ Policy applied successfully" -ForegroundColor Green
    }
    
    # Clean up temp file
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "   ✓ Huge Pages Enabled Successfully!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    Write-Host "IMPORTANT: You MUST restart your computer now!" -ForegroundColor Yellow
    Write-Host "After restart, XMRig will use huge pages for better performance.`n" -ForegroundColor Yellow
    
    $restart = Read-Host "Would you like to restart now? (yes/no)"
    if ($restart -eq "yes") {
        Write-Host "`nRestarting in 10 seconds... Press Ctrl+C to cancel" -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
    else {
        Write-Host "`nPlease restart your computer manually to enable huge pages." -ForegroundColor Yellow
    }
    
    exit 0
}
catch {
    Write-Host "`n❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nManual Configuration:" -ForegroundColor Yellow
    Write-Host "1. Press Win+R and type: gpedit.msc" -ForegroundColor White
    Write-Host "2. Navigate to: Computer Configuration > Windows Settings > Security Settings > Local Policies > User Rights Assignment" -ForegroundColor White
    Write-Host "3. Double-click 'Lock pages in memory'" -ForegroundColor White
    Write-Host "4. Click 'Add User or Group' and add your user: $userName" -ForegroundColor White
    Write-Host "5. Click OK and restart your computer`n" -ForegroundColor White
    
    exit 1
}
