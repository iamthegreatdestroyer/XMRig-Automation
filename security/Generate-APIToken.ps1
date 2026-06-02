# ============================================================================
# GENERATE & STORE API TOKEN - Cryptographically secure, DPAPI-backed
# ============================================================================
# Generates a 32-byte random token, encrypts it with DPAPI (CurrentUser),
# and writes a plaintext runtime copy (restricted permissions) for Python.
#
# Run once at setup. Subsequent runs rotate the token.
# ============================================================================

#Requires -Version 5.1

$SecureStoragePath = "$env:APPDATA\XMRig\secure"
$EncryptedTokenFile = "$SecureStoragePath\api-token.enc"
$RuntimeTokenFile   = "$SecureStoragePath\api-token.txt"

function Write-Log {
    param([string]$Msg, [string]$Color = "Cyan")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $Msg" -ForegroundColor $Color
}

function New-SecureAPIToken {
    # Generate 32 cryptographically random bytes → Base64 token
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 32
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return [System.Convert]::ToBase64String($bytes)
}

function Set-RestrictedPermissions {
    param([string]$FilePath)
    $acl = Get-Acl $FilePath
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $env:USERNAME, "FullControl", "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl $FilePath $acl
}

# Ensure secure storage directory exists
if (-not (Test-Path $SecureStoragePath)) {
    New-Item -Path $SecureStoragePath -ItemType Directory -Force | Out-Null
    Write-Log "Created secure storage: $SecureStoragePath"
}

Write-Log "Generating new API token..." "Yellow"
$token = New-SecureAPIToken

# Encrypt and store via DPAPI
$ss = ConvertTo-SecureString $token -AsPlainText -Force
$encrypted = ConvertFrom-SecureString $ss
Set-Content -Path $EncryptedTokenFile -Value $encrypted -Force
Set-RestrictedPermissions -FilePath $EncryptedTokenFile
Write-Log "Token encrypted and stored: $EncryptedTokenFile" "Green"

# Write plaintext runtime copy (restricted to current user, no commit path)
Set-Content -Path $RuntimeTokenFile -Value $token -Force
Set-RestrictedPermissions -FilePath $RuntimeTokenFile
Write-Log "Runtime token written: $RuntimeTokenFile" "Green"

Write-Log "API token rotation complete. Restart production-start.ps1 to apply." "Cyan"

# Return token for use by caller if dot-sourced
$script:GeneratedAPIToken = $token
