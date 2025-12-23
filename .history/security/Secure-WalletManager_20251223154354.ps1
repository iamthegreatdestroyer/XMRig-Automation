# ============================================================================
# SECURE WALLET MANAGER - DPAPI-Based Wallet Encryption
# ============================================================================
# Implements Windows DPAPI encryption for XMRig wallet addresses
# 
# Security Features:
# - Encryption tied to Windows user profile (CurrentUser scope)
# - File permissions restricted to current user only
# - SecureString memory protection
# - Secure deletion with random overwrite
#
# Author: XMRig Automation Security Module
# License: MIT
# ============================================================================

#Requires -Version 5.1

$ErrorActionPreference = "Stop"
$SecureStoragePath = "$env:APPDATA\XMRig\secure"
$WalletFile = "$SecureStoragePath\wallet.enc"
$ConfigPath = "C:\XMRig\xmrig-6.22.0\config.json"
$LogFile = "$SecureStoragePath\wallet-manager.log"

# ============================================================================
# LOGGING
# ============================================================================

function Write-SecureLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "SECURITY")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    if (-not (Test-Path $SecureStoragePath)) {
        New-Item -Path $SecureStoragePath -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "SECURITY" { "Magenta" }
        default { "Cyan" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

# ============================================================================
# CORE ENCRYPTION FUNCTIONS
# ============================================================================

function Protect-WalletAddress {
    <#
    .SYNOPSIS
        Encrypts a wallet address using Windows DPAPI
    .PARAMETER WalletAddress
        The plaintext wallet address to encrypt
    .EXAMPLE
        Protect-WalletAddress -WalletAddress "48edfHu7V9Z84YzzMa6fUueoELZ9ZRXq..."
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WalletAddress
    )
    
    try {
        Write-SecureLog "Initiating wallet encryption..." "SECURITY"
        
        # Create secure storage directory
        if (-not (Test-Path $SecureStoragePath)) {
            New-Item -Path $SecureStoragePath -ItemType Directory -Force | Out-Null
            Write-SecureLog "Created secure storage directory: $SecureStoragePath" "INFO"
        }
        
        # Encrypt using DPAPI (CurrentUser scope)
        $secureString = ConvertTo-SecureString $WalletAddress -AsPlainText -Force
        $encrypted = ConvertFrom-SecureString $secureString
        
        # Write encrypted data
        Set-Content -Path $WalletFile -Value $encrypted -Force
        
        # Restrict file permissions to current user only
        $acl = Get-Acl $WalletFile
        $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance
        
        # Remove all existing rules
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
        
        # Add rule for current user only
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $env:USERNAME,
            "FullControl",
            "Allow"
        )
        $acl.AddAccessRule($rule)
        Set-Acl $WalletFile $acl
        
        Write-SecureLog "Wallet encrypted and stored securely" "SUCCESS"
        Write-SecureLog "File permissions restricted to: $env:USERNAME" "SECURITY"
        
        # Clear sensitive data from memory
        $secureString.Dispose()
        
        return $true
    }
    catch {
        Write-SecureLog "Encryption failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Unprotect-WalletAddress {
    <#
    .SYNOPSIS
        Decrypts the stored wallet address
    .OUTPUTS
        Plaintext wallet address string
    .EXAMPLE
        $wallet = Unprotect-WalletAddress
    #>
    [CmdletBinding()]
    param()
    
    try {
        if (-not (Test-Path $WalletFile)) {
            Write-SecureLog "No encrypted wallet found at: $WalletFile" "WARNING"
            return $null
        }
        
        Write-SecureLog "Decrypting wallet address..." "SECURITY"
        
        # Read encrypted data
        $encrypted = Get-Content $WalletFile
        
        # Decrypt using DPAPI
        $secureString = ConvertTo-SecureString $encrypted
        
        # Convert to plaintext (secure method)
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
        try {
            $plaintext = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        finally {
            # Zero out BSTR memory
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        
        # Dispose SecureString
        $secureString.Dispose()
        
        Write-SecureLog "Wallet decrypted successfully" "SUCCESS"
        return $plaintext
    }
    catch {
        Write-SecureLog "Decryption failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# ============================================================================
# CONFIG INTEGRATION FUNCTIONS
# ============================================================================

function Update-ConfigWithSecureWallet {
    <#
    .SYNOPSIS
        Extracts wallet from config.json, encrypts it, and replaces with placeholder
    .PARAMETER ConfigFile
        Path to XMRig config.json
    .PARAMETER BackupOriginal
        Create backup before modification
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigFile = $ConfigPath,
        [switch]$BackupOriginal
    )
    
    try {
        if (-not (Test-Path $ConfigFile)) {
            Write-SecureLog "Config file not found: $ConfigFile" "ERROR"
            return $false
        }
        
        Write-SecureLog "Processing config file: $ConfigFile" "INFO"
        
        # Read config
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        
        # Extract wallet from first pool
        $wallet = $config.pools[0].user
        
        if ([string]::IsNullOrEmpty($wallet) -or $wallet -eq "__SECURE_WALLET__") {
            Write-SecureLog "Wallet already secured or empty" "WARNING"
            return $false
        }
        
        # Backup if requested
        if ($BackupOriginal) {
            $backupPath = "$ConfigFile.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $ConfigFile $backupPath
            Write-SecureLog "Backup created: $backupPath" "INFO"
        }
        
        # Encrypt wallet
        $result = Protect-WalletAddress -WalletAddress $wallet
        if (-not $result) {
            return $false
        }
        
        # Replace wallet with placeholder in config
        $config.pools[0].user = "__SECURE_WALLET__"
        
        # Write updated config
        $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
        
        Write-SecureLog "Config updated with secure wallet placeholder" "SUCCESS"
        return $true
    }
    catch {
        Write-SecureLog "Config update failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Get-SecureConfigWallet {
    <#
    .SYNOPSIS
        Returns config JSON with decrypted wallet for XMRig startup
    .PARAMETER ConfigFile
        Path to config.json
    .OUTPUTS
        JSON string with decrypted wallet
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigFile = $ConfigPath
    )
    
    try {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        
        if ($config.pools[0].user -eq "__SECURE_WALLET__") {
            $wallet = Unprotect-WalletAddress
            if ($wallet) {
                $config.pools[0].user = $wallet
            }
            else {
                Write-SecureLog "Could not decrypt wallet - using placeholder" "ERROR"
            }
        }
        
        return ($config | ConvertTo-Json -Depth 10)
    }
    catch {
        Write-SecureLog "Failed to get secure config: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Test-SecureWalletStatus {
    <#
    .SYNOPSIS
        Diagnostic check of secure wallet storage
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              SECURE WALLET STATUS CHECK                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    $status = @{
        StorageExists = Test-Path $SecureStoragePath
        WalletExists  = Test-Path $WalletFile
        CanDecrypt    = $false
        Permissions   = "Unknown"
    }
    
    if ($status.WalletExists) {
        $acl = Get-Acl $WalletFile
        $status.Permissions = ($acl.Access | ForEach-Object { "$($_.IdentityReference): $($_.FileSystemRights)" }) -join "; "
        
        $wallet = Unprotect-WalletAddress
        $status.CanDecrypt = -not [string]::IsNullOrEmpty($wallet)
        
        if ($status.CanDecrypt) {
            $maskedWallet = $wallet.Substring(0, 8) + "..." + $wallet.Substring($wallet.Length - 8)
            Write-Host "  Wallet (masked): $maskedWallet" -ForegroundColor Green
        }
    }
    
    Write-Host "  Storage Path:    $SecureStoragePath" -ForegroundColor Cyan
    Write-Host "  Storage Exists:  $($status.StorageExists)" -ForegroundColor $(if ($status.StorageExists) { "Green" }else { "Red" })
    Write-Host "  Wallet Exists:   $($status.WalletExists)" -ForegroundColor $(if ($status.WalletExists) { "Green" }else { "Red" })
    Write-Host "  Can Decrypt:     $($status.CanDecrypt)" -ForegroundColor $(if ($status.CanDecrypt) { "Green" }else { "Red" })
    Write-Host "  Permissions:     $($status.Permissions)" -ForegroundColor Yellow
    
    return $status
}

function Remove-SecureWallet {
    <#
    .SYNOPSIS
        Securely removes encrypted wallet with random overwrite
    #>
    [CmdletBinding()]
    param()
    
    try {
        if (Test-Path $WalletFile) {
            Write-SecureLog "Initiating secure deletion..." "SECURITY"
            
            # Overwrite with random data before deletion
            $randomBytes = New-Object byte[] 1024
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($randomBytes)
            [System.IO.File]::WriteAllBytes($WalletFile, $randomBytes)
            
            # Delete file
            Remove-Item $WalletFile -Force
            
            Write-SecureLog "Secure wallet removed with random overwrite" "SUCCESS"
            return $true
        }
        else {
            Write-SecureLog "No wallet file to remove" "WARNING"
            return $false
        }
    }
    catch {
        Write-SecureLog "Secure deletion failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# MODULE EXPORT
# ============================================================================

Write-Host "`n  Secure Wallet Manager loaded." -ForegroundColor Green
Write-Host "  Commands: Protect-WalletAddress, Unprotect-WalletAddress," -ForegroundColor Gray
Write-Host "            Update-ConfigWithSecureWallet, Test-SecureWalletStatus`n" -ForegroundColor Gray
