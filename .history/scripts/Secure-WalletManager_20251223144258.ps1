<#
.SYNOPSIS
    Secure Wallet Manager for XMRig Mining Automation
.DESCRIPTION
    Implements DPAPI-based wallet address encryption using Windows Data Protection API.
    Encrypts wallet addresses so they are only decryptable by the current Windows user.
.NOTES
    Author: XMRig-Automation
    Security: Uses Windows DPAPI (CurrentUser scope) - encrypted data is bound to user profile
    Version: 1.0.0
#>

#Requires -Version 5.1

# Configuration
$script:SecureStoragePath = Join-Path $env:APPDATA "XMRig\secure"
$script:WalletEncFile = Join-Path $script:SecureStoragePath "wallet.enc"
$script:ConfigPath = "C:\XMRig\xmrig-6.22.0\config.json"
$script:LogPath = Join-Path $env:APPDATA "XMRig\logs\wallet-security.log"

#region Logging

function Write-SecureLog {
    <#
    .SYNOPSIS
        Writes timestamped log entries without exposing sensitive data
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')][string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path $script:LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $script:LogPath -Value $logEntry -ErrorAction SilentlyContinue
    
    $color = switch ($Level) {
        'INFO'    { 'Cyan' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
    }
    Write-Host $logEntry -ForegroundColor $color
}

#endregion

#region File Security

function Set-SecureFilePermissions {
    <#
    .SYNOPSIS
        Restricts file permissions to current user only (removes inheritance, grants FullControl)
    #>
    param([Parameter(Mandatory)][string]$FilePath)
    
    try {
        $acl = Get-Acl -Path $FilePath
        
        # Disable inheritance and remove inherited rules
        $acl.SetAccessRuleProtection($true, $false)
        
        # Remove all existing access rules
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
        
        # Add FullControl for current user only
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($accessRule)
        
        Set-Acl -Path $FilePath -AclObject $acl
        Write-SecureLog "File permissions restricted to: $currentUser" -Level 'SUCCESS'
        return $true
    }
    catch {
        Write-SecureLog "Failed to set file permissions: $_" -Level 'ERROR'
        return $false
    }
}

function Initialize-SecureStorage {
    <#
    .SYNOPSIS
        Creates secure storage directory with restricted permissions
    #>
    try {
        if (-not (Test-Path $script:SecureStoragePath)) {
            $dir = New-Item -ItemType Directory -Path $script:SecureStoragePath -Force
            
            # Restrict directory permissions
            $acl = Get-Acl -Path $dir.FullName
            $acl.SetAccessRuleProtection($true, $false)
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
            
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $currentUser,
                [System.Security.AccessControl.FileSystemRights]::FullControl,
                [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor 
                [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $acl.AddAccessRule($accessRule)
            Set-Acl -Path $dir.FullName -AclObject $acl
            
            Write-SecureLog "Secure storage initialized at: $script:SecureStoragePath" -Level 'SUCCESS'
        }
        return $true
    }
    catch {
        Write-SecureLog "Failed to initialize secure storage: $_" -Level 'ERROR'
        return $false
    }
}

#endregion

#region Core Cryptographic Functions

function Protect-WalletAddress {
    <#
    .SYNOPSIS
        Encrypts wallet address using Windows DPAPI (CurrentUser scope)
    .PARAMETER WalletAddress
        The plaintext wallet address to encrypt
    .OUTPUTS
        [bool] True if encryption succeeded, False otherwise
    .EXAMPLE
        Protect-WalletAddress -WalletAddress "48edfHu7V9Z84YzzMa6fUueoELZ9ZRXq9VetWzYGzKt52XU5xvqgzYnDK9URnRoJMk1j8nLAEo..."
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$WalletAddress
    )
    
    process {
        try {
            # Validate wallet format (basic check for XMR-style addresses)
            if ($WalletAddress.Length -lt 90 -or $WalletAddress -notmatch '^[48][0-9A-Za-z]{94,}') {
                Write-SecureLog "Warning: Wallet address format may be invalid (expected XMR/RTM format)" -Level 'WARN'
            }
            
            # Initialize secure storage
            if (-not (Initialize-SecureStorage)) {
                throw "Failed to initialize secure storage"
            }
            
            # Convert to SecureString and encrypt using DPAPI
            $secureString = ConvertTo-SecureString -String $WalletAddress -AsPlainText -Force
            $encryptedData = ConvertFrom-SecureString -SecureString $secureString
            
            # Write to secure file
            Set-Content -Path $script:WalletEncFile -Value $encryptedData -Force -NoNewline
            
            # Restrict file permissions
            if (-not (Set-SecureFilePermissions -FilePath $script:WalletEncFile)) {
                throw "Failed to set secure file permissions"
            }
            
            # Securely clear the SecureString from memory
            $secureString.Dispose()
            
            Write-SecureLog "Wallet address encrypted and stored securely" -Level 'SUCCESS'
            Write-SecureLog "Encrypted file: $script:WalletEncFile" -Level 'INFO'
            
            return $true
        }
        catch {
            Write-SecureLog "Encryption failed: $_" -Level 'ERROR'
            return $false
        }
    }
}

function Unprotect-WalletAddress {
    <#
    .SYNOPSIS
        Decrypts wallet address from secure storage using DPAPI
    .OUTPUTS
        [string] Decrypted wallet address, or $null on failure
    .EXAMPLE
        $wallet = Unprotect-WalletAddress
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        if (-not (Test-Path $script:WalletEncFile)) {
            Write-SecureLog "Encrypted wallet file not found: $script:WalletEncFile" -Level 'ERROR'
            return $null
        }
        
        # Read encrypted data
        $encryptedData = Get-Content -Path $script:WalletEncFile -Raw
        
        if ([string]::IsNullOrWhiteSpace($encryptedData)) {
            Write-SecureLog "Encrypted wallet file is empty" -Level 'ERROR'
            return $null
        }
        
        # Decrypt using DPAPI (bound to current user)
        $secureString = ConvertTo-SecureString -String $encryptedData
        
        # Convert SecureString to plaintext
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
        try {
            $walletAddress = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            # Zero out BSTR memory
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        
        # Dispose SecureString
        $secureString.Dispose()
        
        Write-SecureLog "Wallet address decrypted successfully" -Level 'SUCCESS'
        return $walletAddress
    }
    catch {
        Write-SecureLog "Decryption failed (may require original user context): $_" -Level 'ERROR'
        return $null
    }
}

#endregion

#region Config Integration

function Update-ConfigWithSecureWallet {
    <#
    .SYNOPSIS
        Updates XMRig config.json to use securely stored wallet
    .PARAMETER ConfigPath
        Path to config.json (defaults to standard XMRig location)
    .PARAMETER BackupOriginal
        If true, creates a backup of the original config
    .EXAMPLE
        Update-ConfigWithSecureWallet -BackupOriginal
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath = $script:ConfigPath,
        [switch]$BackupOriginal
    )
    
    try {
        if (-not (Test-Path $ConfigPath)) {
            Write-SecureLog "Config file not found: $ConfigPath" -Level 'ERROR'
            return $false
        }
        
        # Backup if requested
        if ($BackupOriginal) {
            $backupPath = "$ConfigPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Path $ConfigPath -Destination $backupPath -Force
            Write-SecureLog "Config backup created: $backupPath" -Level 'INFO'
        }
        
        # Read config
        $configContent = Get-Content -Path $ConfigPath -Raw
        $config = $configContent | ConvertFrom-Json
        
        # Extract current wallet from pools
        $currentWallet = $null
        if ($config.pools -and $config.pools.Count -gt 0) {
            $currentWallet = $config.pools[0].user
            
            if ($currentWallet -and $currentWallet -ne "YOUR_WALLET_ADDRESS" -and 
                $currentWallet -ne "__SECURE_WALLET__") {
                
                # Encrypt and store the wallet
                if (-not (Protect-WalletAddress -WalletAddress $currentWallet)) {
                    throw "Failed to encrypt wallet address"
                }
                
                # Replace wallet in config with placeholder
                foreach ($pool in $config.pools) {
                    if ($pool.user -eq $currentWallet) {
                        $pool.user = "__SECURE_WALLET__"
                    }
                }
                
                # Save modified config
                $config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Force
                Write-SecureLog "Config updated with secure wallet placeholder" -Level 'SUCCESS'
            }
            else {
                Write-SecureLog "No wallet to secure (already placeholder or not set)" -Level 'WARN'
            }
        }
        
        return $true
    }
    catch {
        Write-SecureLog "Config update failed: $_" -Level 'ERROR'
        return $false
    }
}

function Get-SecureConfigWallet {
    <#
    .SYNOPSIS
        Returns config JSON with decrypted wallet for XMRig startup
    .PARAMETER ConfigPath
        Path to config.json
    .OUTPUTS
        [string] Full config JSON with wallet replaced, or $null on failure
    #>
    [CmdletBinding()]
    param([string]$ConfigPath = $script:ConfigPath)
    
    try {
        if (-not (Test-Path $ConfigPath)) {
            Write-SecureLog "Config file not found: $ConfigPath" -Level 'ERROR'
            return $null
        }
        
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        
        # Check if using secure wallet placeholder
        $needsDecryption = $false
        foreach ($pool in $config.pools) {
            if ($pool.user -eq "__SECURE_WALLET__") {
                $needsDecryption = $true
                break
            }
        }
        
        if ($needsDecryption) {
            $wallet = Unprotect-WalletAddress
            if (-not $wallet) {
                throw "Failed to decrypt wallet address"
            }
            
            # Replace placeholder with actual wallet
            foreach ($pool in $config.pools) {
                if ($pool.user -eq "__SECURE_WALLET__") {
                    $pool.user = $wallet
                }
            }
        }
        
        return ($config | ConvertTo-Json -Depth 10)
    }
    catch {
        Write-SecureLog "Failed to get secure config: $_" -Level 'ERROR'
        return $null
    }
}

#endregion

#region Utility Functions

function Test-SecureWalletStatus {
    <#
    .SYNOPSIS
        Checks status of secure wallet storage
    #>
    Write-Host "`n=== Secure Wallet Status ===" -ForegroundColor Cyan
    
    $status = @{
        StorageExists = Test-Path $script:SecureStoragePath
        WalletEncrypted = Test-Path $script:WalletEncFile
        ConfigExists = Test-Path $script:ConfigPath
    }
    
    Write-Host "Secure Storage Path: $script:SecureStoragePath"
    Write-Host "  Exists: $($status.StorageExists)" -ForegroundColor $(if($status.StorageExists){'Green'}else{'Yellow'})
    
    Write-Host "Encrypted Wallet: $script:WalletEncFile"
    Write-Host "  Exists: $($status.WalletEncrypted)" -ForegroundColor $(if($status.WalletEncrypted){'Green'}else{'Yellow'})
    
    if ($status.WalletEncrypted) {
        $fileInfo = Get-Item $script:WalletEncFile
        Write-Host "  Size: $($fileInfo.Length) bytes"
        Write-Host "  Modified: $($fileInfo.LastWriteTime)"
    }
    
    Write-Host "Config: $script:ConfigPath"
    Write-Host "  Exists: $($status.ConfigExists)" -ForegroundColor $(if($status.ConfigExists){'Green'}else{'Red'})
    
    return $status
}

function Remove-SecureWallet {
    <#
    .SYNOPSIS
        Securely removes encrypted wallet data
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Force)
    
    if (Test-Path $script:WalletEncFile) {
        if ($Force -or $PSCmdlet.ShouldProcess($script:WalletEncFile, "Remove encrypted wallet")) {
            # Overwrite with random data before deletion (secure wipe)
            $randomBytes = [byte[]]::new(256)
            [System.Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
            [System.IO.File]::WriteAllBytes($script:WalletEncFile, $randomBytes)
            
            Remove-Item -Path $script:WalletEncFile -Force
            Write-SecureLog "Encrypted wallet securely removed" -Level 'SUCCESS'
        }
    }
    else {
        Write-SecureLog "No encrypted wallet file found" -Level 'WARN'
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Protect-WalletAddress',
    'Unprotect-WalletAddress', 
    'Update-ConfigWithSecureWallet',
    'Get-SecureConfigWallet',
    'Test-SecureWalletStatus',
    'Remove-SecureWallet'
) -ErrorAction SilentlyContinue

# Interactive mode when run directly
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║          XMRig Secure Wallet Manager v1.0                    ║
║          DPAPI Encryption (CurrentUser Scope)                ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

    Write-Host "Available Commands:" -ForegroundColor Yellow
    Write-Host "  Protect-WalletAddress -WalletAddress '<wallet>'" -ForegroundColor White
    Write-Host "  Unprotect-WalletAddress" -ForegroundColor White
    Write-Host "  Update-ConfigWithSecureWallet -BackupOriginal" -ForegroundColor White
    Write-Host "  Get-SecureConfigWallet" -ForegroundColor White
    Write-Host "  Test-SecureWalletStatus" -ForegroundColor White
    Write-Host "  Remove-SecureWallet -Force" -ForegroundColor White
    Write-Host ""
    
    Test-SecureWalletStatus
}
