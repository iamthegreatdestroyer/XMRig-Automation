#Requires -Version 5.1
<#
.SYNOPSIS
    Script Integrity Verification System for XMRig Mining Automation
.DESCRIPTION
    Provides SHA-256 based integrity verification for PowerShell scripts.
    Detects tampering and blocks execution of modified scripts.
.AUTHOR
    XMRig-Automation Security Module
.VERSION
    1.0.0
#>

# Configuration
$Script:IntegrityConfig = @{
    ProjectRoot    = "C:\Users\sgbil\XMRig-Automation"
    ManifestFile   = "C:\Users\sgbil\XMRig-Automation\security\script-hashes.json"
    LogFile        = "C:\Users\sgbil\XMRig-Automation\logs\integrity-verification.log"
    ExcludePattern = @("*test*", "*backup*", "*old*")
    ExcludeDirs    = @(".history", "node_modules", ".git")
}

#region Logging Functions
function Write-IntegrityLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SECURITY")][string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path $Script:IntegrityConfig.LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $Script:IntegrityConfig.LogFile -Value $logEntry -ErrorAction SilentlyContinue
    
    switch ($Level) {
        "ERROR"    { Write-Host $logEntry -ForegroundColor Red }
        "WARN"     { Write-Host $logEntry -ForegroundColor Yellow }
        "SECURITY" { Write-Host $logEntry -ForegroundColor Magenta }
        default    { Write-Host $logEntry -ForegroundColor Gray }
    }
}
#endregion

#region Hash Functions
function Get-FileHashSHA256 {
    param([Parameter(Mandatory)][string]$FilePath)
    
    try {
        if (-not (Test-Path $FilePath)) {
            throw "File not found: $FilePath"
        }
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop
        return $hash.Hash
    }
    catch {
        Write-IntegrityLog "Failed to hash file: $FilePath - $_" -Level ERROR
        return $null
    }
}

function Get-MasterHash {
    param([Parameter(Mandatory)][hashtable]$Manifest)
    
    # Create deterministic string from all hashes
    $sortedHashes = $Manifest.Scripts.GetEnumerator() | 
        Sort-Object Key | 
        ForEach-Object { "$($_.Key):$($_.Value.Hash)" }
    
    $combinedString = $sortedHashes -join "|"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combinedString)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hashBytes).Replace("-", "")
}
#endregion

#region Core Functions
function New-ScriptHashes {
    <#
    .SYNOPSIS
        Generates SHA-256 hashes for all PowerShell scripts in the project
    .OUTPUTS
        Returns the manifest object and saves to JSON file
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    $projectRoot = $Script:IntegrityConfig.ProjectRoot
    $manifestPath = $Script:IntegrityConfig.ManifestFile
    
    # Check for existing manifest
    if ((Test-Path $manifestPath) -and -not $Force) {
        Write-IntegrityLog "Manifest exists. Use -Force to regenerate." -Level WARN
        return $null
    }
    
    Write-IntegrityLog "Generating script hashes for: $projectRoot" -Level INFO
    
    # Find all PowerShell scripts
    $scripts = Get-ChildItem -Path $projectRoot -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { 
            $exclude = $false
            foreach ($pattern in $Script:IntegrityConfig.ExcludePattern) {
                if ($_.Name -like $pattern) { $exclude = $true; break }
            }
            -not $exclude
        }
    
    $manifest = @{
        Version     = "1.0"
        Generated   = (Get-Date -Format "o")
        Machine     = $env:COMPUTERNAME
        ScriptCount = 0
        Scripts     = @{}
        MasterHash  = ""
    }
    
    foreach ($script in $scripts) {
        $relativePath = $script.FullName.Replace($projectRoot, "").TrimStart("\", "/")
        $hash = Get-FileHashSHA256 -FilePath $script.FullName
        
        if ($hash) {
            $manifest.Scripts[$relativePath] = @{
                Hash         = $hash
                Size         = $script.Length
                LastModified = $script.LastWriteTime.ToString("o")
            }
            $manifest.ScriptCount++
            Write-IntegrityLog "Hashed: $relativePath" -Level INFO
        }
    }
    
    # Generate master hash (signs the manifest)
    $manifest.MasterHash = Get-MasterHash -Manifest $manifest
    
    # Ensure security directory exists
    $securityDir = Split-Path $manifestPath -Parent
    if (-not (Test-Path $securityDir)) {
        New-Item -Path $securityDir -ItemType Directory -Force | Out-Null
    }
    
    # Save manifest
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
    
    Write-IntegrityLog "Manifest saved: $manifestPath (Master: $($manifest.MasterHash.Substring(0,16))...)" -Level INFO
    Write-IntegrityLog "Total scripts hashed: $($manifest.ScriptCount)" -Level INFO
    
    return $manifest
}

function Test-ScriptIntegrity {
    <#
    .SYNOPSIS
        Verifies all scripts against stored hashes
    .OUTPUTS
        PSCustomObject with verification results
    #>
    [CmdletBinding()]
    param(
        [string]$SpecificScript = $null
    )
    
    $manifestPath = $Script:IntegrityConfig.ManifestFile
    $projectRoot = $Script:IntegrityConfig.ProjectRoot
    
    # Load manifest
    if (-not (Test-Path $manifestPath)) {
        Write-IntegrityLog "Hash manifest not found! Run New-ScriptHashes first." -Level ERROR
        return @{ Status = "NO_MANIFEST"; Passed = $false; Details = @() }
    }
    
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-IntegrityLog "Failed to parse manifest: $_" -Level ERROR
        return @{ Status = "CORRUPT_MANIFEST"; Passed = $false; Details = @() }
    }
    
    # Verify master hash first (detect manifest tampering)
    $manifestHash = @{ Scripts = @{} }
    foreach ($prop in $manifest.Scripts.PSObject.Properties) {
        $manifestHash.Scripts[$prop.Name] = @{ Hash = $prop.Value.Hash }
    }
    $calculatedMaster = Get-MasterHash -Manifest $manifestHash
    
    if ($calculatedMaster -ne $manifest.MasterHash) {
        Write-IntegrityLog "MANIFEST TAMPERING DETECTED! Master hash mismatch." -Level SECURITY
        return @{ Status = "MANIFEST_TAMPERED"; Passed = $false; Details = @() }
    }
    
    $results = @{
        Status      = "VERIFIED"
        Passed      = $true
        Timestamp   = Get-Date -Format "o"
        TotalFiles  = 0
        PassedCount = 0
        FailedCount = 0
        MissingCount = 0
        Details     = @()
    }
    
    # Determine scripts to verify
    $scriptsToCheck = if ($SpecificScript) {
        @{ $SpecificScript = $manifest.Scripts.$SpecificScript }
    } else {
        $manifest.Scripts.PSObject.Properties | ForEach-Object { @{ $_.Name = $_.Value } }
    }
    
    foreach ($entry in $manifest.Scripts.PSObject.Properties) {
        $relativePath = $entry.Name
        $storedHash = $entry.Value.Hash
        $fullPath = Join-Path $projectRoot $relativePath
        
        $results.TotalFiles++
        $detail = @{
            Script = $relativePath
            Status = "UNKNOWN"
            StoredHash = $storedHash.Substring(0, 16) + "..."
            CurrentHash = ""
        }
        
        if (-not (Test-Path $fullPath)) {
            $detail.Status = "MISSING"
            $results.MissingCount++
            $results.Passed = $false
            Write-IntegrityLog "MISSING: $relativePath" -Level WARN
        }
        else {
            $currentHash = Get-FileHashSHA256 -FilePath $fullPath
            $detail.CurrentHash = $currentHash.Substring(0, 16) + "..."
            
            if ($currentHash -eq $storedHash) {
                $detail.Status = "PASSED"
                $results.PassedCount++
            }
            else {
                $detail.Status = "FAILED"
                $results.FailedCount++
                $results.Passed = $false
                Write-IntegrityLog "TAMPERED: $relativePath" -Level SECURITY
            }
        }
        
        $results.Details += [PSCustomObject]$detail
    }
    
    $results.Status = if ($results.Passed) { "ALL_VERIFIED" } else { "INTEGRITY_FAILURE" }
    
    Write-IntegrityLog "Verification complete: $($results.PassedCount)/$($results.TotalFiles) passed" -Level $(if ($results.Passed) { "INFO" } else { "SECURITY" })
    
    return [PSCustomObject]$results
}

function Invoke-ProtectedScript {
    <#
    .SYNOPSIS
        Executes a script only if integrity verification passes
    .PARAMETER ScriptPath
        Path to the script to execute (relative or absolute)
    .PARAMETER Arguments
        Arguments to pass to the script
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [switch]$BypassVerification
    )
    
    $projectRoot = $Script:IntegrityConfig.ProjectRoot
    
    # Resolve path
    $fullPath = if ([System.IO.Path]::IsPathRooted($ScriptPath)) {
        $ScriptPath
    } else {
        Join-Path $projectRoot $ScriptPath
    }
    
    $relativePath = $fullPath.Replace($projectRoot, "").TrimStart("\", "/")
    
    Write-IntegrityLog "Protected execution request: $relativePath" -Level INFO
    
    if (-not (Test-Path $fullPath)) {
        Write-IntegrityLog "Script not found: $fullPath" -Level ERROR
        throw "Script not found: $fullPath"
    }
    
    if ($BypassVerification) {
        Write-IntegrityLog "BYPASS: Verification skipped for $relativePath" -Level WARN
    }
    else {
        # Verify integrity
        $verification = Test-ScriptIntegrity
        
        if (-not $verification.Passed) {
            Write-IntegrityLog "BLOCKED: Execution denied due to integrity failure" -Level SECURITY
            throw "Script integrity verification failed. Execution blocked for security."
        }
        
        Write-IntegrityLog "VERIFIED: Integrity check passed for $relativePath" -Level INFO
    }
    
    # Execute the script
    try {
        Write-IntegrityLog "EXECUTING: $relativePath" -Level INFO
        & $fullPath @Arguments
        Write-IntegrityLog "COMPLETED: $relativePath" -Level INFO
    }
    catch {
        Write-IntegrityLog "EXECUTION ERROR: $relativePath - $_" -Level ERROR
        throw
    }
}

function Initialize-IntegrityOnStartup {
    <#
    .SYNOPSIS
        Initializes integrity verification on system startup
    #>
    [CmdletBinding()]
    param()
    
    Write-IntegrityLog "=== XMRig Automation Startup Integrity Check ===" -Level INFO
    
    $verification = Test-ScriptIntegrity
    
    if ($verification.Status -eq "NO_MANIFEST") {
        Write-IntegrityLog "First run detected. Generating initial hash manifest..." -Level WARN
        New-ScriptHashes -Force
        return $true
    }
    
    if (-not $verification.Passed) {
        Write-IntegrityLog "!!! SECURITY ALERT: Script integrity compromised !!!" -Level SECURITY
        Write-IntegrityLog "Failed scripts:" -Level SECURITY
        $verification.Details | Where-Object { $_.Status -ne "PASSED" } | ForEach-Object {
            Write-IntegrityLog "  - $($_.Script): $($_.Status)" -Level SECURITY
        }
        return $false
    }
    
    Write-IntegrityLog "All scripts verified successfully." -Level INFO
    return $true
}
#endregion

# Export functions
Export-ModuleMember -Function @(
    'New-ScriptHashes',
    'Test-ScriptIntegrity', 
    'Invoke-ProtectedScript',
    'Initialize-IntegrityOnStartup',
    'Write-IntegrityLog'
) -ErrorAction SilentlyContinue

# If running directly (not as module), show usage
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "`n=== Script Integrity Verifier ===" -ForegroundColor Cyan
    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "  New-ScriptHashes [-Force]           - Generate hash manifest"
    Write-Host "  Test-ScriptIntegrity                - Verify all scripts"
    Write-Host "  Invoke-ProtectedScript -ScriptPath  - Run script with verification"
    Write-Host "  Initialize-IntegrityOnStartup       - Startup check`n"
}
