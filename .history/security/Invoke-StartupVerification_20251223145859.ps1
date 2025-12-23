#Requires -Version 5.1
<#
.SYNOPSIS
    Startup integration script for integrity verification
.DESCRIPTION
    Dot-source this script at the beginning of any mining automation script
    to enforce integrity verification before execution.
#>

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $PSScriptRoot

# Import the integrity verifier
$verifierPath = Join-Path $ScriptRoot "security\Script-IntegrityVerifier.ps1"
if (Test-Path $verifierPath) {
    . $verifierPath
    
    # Run startup verification
    $verified = Initialize-IntegrityOnStartup
    
    if (-not $verified) {
        Write-Host "`n[SECURITY] Integrity verification FAILED!" -ForegroundColor Red
        Write-Host "[SECURITY] Scripts may have been tampered with." -ForegroundColor Red
        Write-Host "[SECURITY] Mining automation BLOCKED for security.`n" -ForegroundColor Red
        
        $response = Read-Host "Override and continue anyway? (type 'OVERRIDE' to confirm)"
        if ($response -ne "OVERRIDE") {
            Write-Host "Exiting for security. Review logs at: logs\integrity-verification.log" -ForegroundColor Yellow
            exit 1
        }
        Write-IntegrityLog "USER OVERRIDE: Continued despite integrity failure" -Level SECURITY
    }
}
else {
    Write-Warning "Integrity verifier not found. Running without verification."
}
