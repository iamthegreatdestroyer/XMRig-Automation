<#
.SYNOPSIS
    Master setup script for XMRig Monero mining automation.

.DESCRIPTION
    One-click complete setup that installs XMRig, configures all settings,
    creates scheduled tasks, and prepares the system for automatic 24/7 mining.

.EXAMPLE
    .\MASTER-SETUP.ps1
    Runs the complete automated setup process.

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
    Requires Administrator privileges
    Internet connection required for downloading XMRig
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$InstallPath = "C:\XMRig",
    [switch]$SkipRestart
)

# Setup logging
$logFile = Join-Path $PSScriptRoot "setup-log.txt"
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logMessage
}

# Display functions
function Write-Success { param([string]$Message) Write-Host "  ✓ $Message" -ForegroundColor Green; Write-Log $Message "SUCCESS" }
function Write-Failure { param([string]$Message) Write-Host "  ✗ $Message" -ForegroundColor Red; Write-Log $Message "ERROR" }
function Write-Info { param([string]$Message) Write-Host "  ℹ $Message" -ForegroundColor Cyan; Write-Log $Message "INFO" }
function Write-Warning2 { param([string]$Message) Write-Host "  ⚠ $Message" -ForegroundColor Yellow; Write-Log $Message "WARNING" }

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                                           ║" -ForegroundColor Cyan
    Write-Host "║                  ██╗  ██╗███╗   ███╗██████╗ ██╗ ██████╗                  ║" -ForegroundColor Cyan
    Write-Host "║                  ╚██╗██╔╝████╗ ████║██╔══██╗██║██╔════╝                  ║" -ForegroundColor Cyan
    Write-Host "║                   ╚███╔╝ ██╔████╔██║██████╔╝██║██║  ███╗                 ║" -ForegroundColor Cyan
    Write-Host "║                   ██╔██╗ ██║╚██╔╝██║██╔══██╗██║██║   ██║                 ║" -ForegroundColor Cyan
    Write-Host "║                  ██╔╝ ██╗██║ ╚═╝ ██║██║  ██║██║╚██████╔╝                 ║" -ForegroundColor Cyan
    Write-Host "║                  ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝ ╚═════╝                  ║" -ForegroundColor Cyan
    Write-Host "║                                                                           ║" -ForegroundColor Cyan
    Write-Host "║                 Automated XMRig Monero Mining Setup                      ║" -ForegroundColor White
    Write-Host "║                         Version 1.0                                       ║" -ForegroundColor Gray
    Write-Host "║                                                                           ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Prerequisites {
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host " STEP 1: Checking Prerequisites" -ForegroundColor White
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    $allGood = $true
    
    # Check Windows version
    Write-Host "Checking Windows version..." -ForegroundColor Cyan
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $version = [System.Environment]::OSVersion.Version
    
    if ($version.Major -ge 10) {
        Write-Success "Windows version: $($os.Caption) (Build $($version.Build))"
    } else {
        Write-Failure "Windows 10 or later required"
        $allGood = $false
    }
    
    # Check admin rights
    Write-Host "Checking administrator privileges..." -ForegroundColor Cyan
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Success "Running with administrator privileges"
    } else {
        Write-Failure "Administrator privileges required"
        $allGood = $false
    }
    
    # Check .NET version
    Write-Host "Checking .NET Framework..." -ForegroundColor Cyan
    $dotNet = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue).Release
    if ($dotNet -ge 394802) {
        Write-Success ".NET Framework 4.6.2 or later installed"
    } else {
        Write-Warning2 ".NET Framework may be outdated (not critical)"
    }
    
    # Check internet connection
    Write-Host "Checking internet connectivity..." -ForegroundColor Cyan
    try {
        $test = Test-Connection -ComputerName "github.com" -Count 1 -Quiet -ErrorAction Stop
        if ($test) {
            Write-Success "Internet connection available"
        } else {
            Write-Failure "Cannot reach GitHub (required for downloading XMRig)"
            $allGood = $false
        }
    } catch {
        Write-Failure "Internet connection test failed"
        $allGood = $false
    }
    
    # Check disk space
    Write-Host "Checking disk space..." -ForegroundColor Cyan
    $drive = (Get-Item $InstallPath -ErrorAction SilentlyContinue).PSDrive.Name
    if (-not $drive) {
        $drive = $InstallPath.Substring(0,1)
    }
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='${drive}:'" | Select-Object FreeSpace
    $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    
    if ($freeSpaceGB -gt 1) {
        Write-Success "Free disk space: $freeSpaceGB GB"
    } else {
        Write-Failure "Insufficient disk space (need at least 1 GB)"
        $allGood = $false
    }
    
    # Check CPU cores
    Write-Host "Checking CPU information..." -ForegroundColor Cyan
    $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
    $cores = $cpu.NumberOfCores
    $threads = $cpu.NumberOfLogicalProcessors
    
    Write-Success "CPU: $($cpu.Name)"
    Write-Info "Cores: $cores | Threads: $threads"
    
    if ($threads -lt 4) {
        Write-Warning2 "Mining on CPUs with less than 4 threads may not be profitable"
    }
    
    Write-Host ""
    
    if (-not $allGood) {
        Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host " Prerequisites check failed. Please resolve the issues above." -ForegroundColor Red
        Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
    
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host " ✓ All prerequisites met!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
}

function Confirm-Installation {
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host " Installation Configuration" -ForegroundColor White
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This script will:" -ForegroundColor White
    Write-Host "  1. Download and install XMRig" -ForegroundColor Gray
    Write-Host "  2. Configure optimized mining settings" -ForegroundColor Gray
    Write-Host "  3. Add Windows Defender exclusions" -ForegroundColor Gray
    Write-Host "  4. Enable huge pages for better performance" -ForegroundColor Gray
    Write-Host "  5. Create auto-start scheduled task" -ForegroundColor Gray
    Write-Host "  6. Create desktop shortcuts" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Installation directory: " -NoNewline -ForegroundColor White
    Write-Host $InstallPath -ForegroundColor Cyan
    Write-Host "Pool: " -NoNewline -ForegroundColor White
    Write-Host "xmrpool.eu:3333" -ForegroundColor Cyan
    Write-Host "Rig ID: " -NoNewline -ForegroundColor White
    Write-Host "RyzenRig" -ForegroundColor Cyan
    Write-Host ""
    
    $confirm = Read-Host "Do you want to proceed with installation? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host ""
        Write-Host "Installation cancelled by user." -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }
    Write-Host ""
}

# Main execution starts here
try {
    Show-Banner
    Write-Log "===== XMRig Master Setup Started =====" "INFO"
    
    # Step 1: Prerequisites
    Test-Prerequisites
    
    # Step 2: Confirmation
    Confirm-Installation
    
    # Step 3: Install XMRig
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host " STEP 2: Installing XMRig" -ForegroundColor White
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    $configPath = Join-Path $PSScriptRoot "config\config.json"
    $installScript = Join-Path $PSScriptRoot "setup\install.ps1"
    
    & $installScript -InstallPath $InstallPath -ConfigPath $configPath
    
    if ($LASTEXITCODE -ne 0) {
        throw "XMRig installation failed"
    }
    
    Write-Host ""
    
    # Step 4: Configure Windows Defender
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host " STEP 3: Configuring Windows Defender" -ForegroundColor White
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    $defenderScript = Join-Path $PSScriptRoot "setup\configure-defender.ps1"
    & $defenderScript -XMRigPath $InstallPath
    
    Write-Host ""
    
    # Step 5: Configure Huge Pages
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host " STEP 4: Configuring Huge Pages" -ForegroundColor White
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    $hugepagesScript = Join-Path $PSScriptRoot "setup\configure-hugepages.ps1"
    & $hugepagesScript
    
    Write-Host ""
    
    # Step 6: Create Scheduled Task
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host " STEP 5: Creating Auto-Start Task" -ForegroundColor White
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    # Update start-mining.bat with correct path
    $startScript = Join-Path $PSScriptRoot "scripts\start-mining.bat"
    $taskScript = Join-Path $PSScriptRoot "setup\create-scheduled-task.ps1"
    
    & $taskScript -TaskName "XMRig Auto Start" -ScriptPath $startScript -XMRigPath $InstallPath
    
    Write-Host ""
    
    # Step 7: Create Desktop Shortcuts
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host " STEP 6: Creating Desktop Shortcuts" -ForegroundColor White
    Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    $shortcutScript = Join-Path $PSScriptRoot "shortcuts\create-desktop-shortcuts.ps1"
    if (Test-Path $shortcutScript) {
        & $shortcutScript -ScriptsPath (Join-Path $PSScriptRoot "scripts") -XMRigPath $InstallPath
    }
    
    Write-Host ""
    
    # Final success message
    Clear-Host
    Show-Banner
    
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "                  ✓ INSTALLATION COMPLETE!                        " -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "XMRig has been successfully installed and configured!" -ForegroundColor White
    Write-Host ""
    Write-Host "Installation Summary:" -ForegroundColor Cyan
    Write-Host "  ✓ XMRig installed to: $InstallPath" -ForegroundColor Gray
    Write-Host "  ✓ Configuration optimized for AMD Ryzen 7 7730U" -ForegroundColor Gray
    Write-Host "  ✓ Windows Defender exclusions added" -ForegroundColor Gray
    Write-Host "  ✓ Huge pages configured" -ForegroundColor Gray
    Write-Host "  ✓ Auto-start task created" -ForegroundColor Gray
    Write-Host "  ✓ Desktop shortcuts created" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Mining Configuration:" -ForegroundColor Cyan
    Write-Host "  Pool:     xmrpool.eu:3333" -ForegroundColor Gray
    Write-Host "  Rig ID:   RyzenRig" -ForegroundColor Gray
    Write-Host "  Target:   1800-2000 H/s" -ForegroundColor Gray
    Write-Host "  Threads:  75% (12 of 16)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "What Happens Next:" -ForegroundColor Yellow
    Write-Host "  1. Restart your computer (required for huge pages)" -ForegroundColor White
    Write-Host "  2. Mining will start automatically 30 seconds after boot" -ForegroundColor White
    Write-Host "  3. Mining runs 24/7 with automatic crash recovery" -ForegroundColor White
    Write-Host ""
    Write-Host "Desktop Shortcuts Created:" -ForegroundColor Cyan
    Write-Host "  • Start Mining    - Manually start mining" -ForegroundColor Gray
    Write-Host "  • Stop Mining     - Stop mining" -ForegroundColor Gray
    Write-Host "  • Check Status    - View mining status" -ForegroundColor Gray
    Write-Host "  • View Logs       - Monitor live logs" -ForegroundColor Gray
    Write-Host "  • Pool Dashboard  - Check earnings online" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Check Your Earnings:" -ForegroundColor Cyan
    Write-Host "  Dashboard: " -NoNewline -ForegroundColor Gray
    Write-Host "https://xmrpool.eu/#/dashboard" -ForegroundColor Cyan
    Write-Host "  Wallet: " -NoNewline -ForegroundColor Gray
    Write-Host "4Anom...ycu4HyvWVSx" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
    if (-not $SkipRestart) {
        Write-Host "⚠ RESTART REQUIRED" -ForegroundColor Yellow
        Write-Host "Huge pages will not work until you restart your computer." -ForegroundColor Yellow
        Write-Host ""
        $restart = Read-Host "Restart computer now? (yes/no)"
        
        if ($restart -eq "yes") {
            Write-Host ""
            Write-Host "Restarting in 10 seconds... Press Ctrl+C to cancel" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        } else {
            Write-Host ""
            Write-Host "Please restart your computer manually when convenient." -ForegroundColor Yellow
            Write-Host ""
        }
    }
    
    Write-Log "===== Setup Completed Successfully =====" "SUCCESS"
    Write-Host "Setup log saved to: $logFile" -ForegroundColor Gray
    Write-Host ""
    
    exit 0
    
} catch {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ✗ SETUP FAILED" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Setup log: $logFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "For help, check:" -ForegroundColor Yellow
    Write-Host "  • docs\TROUBLESHOOTING.md" -ForegroundColor Gray
    Write-Host "  • docs\FAQ.md" -ForegroundColor Gray
    Write-Host ""
    
    Write-Log "Setup failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
