#!/usr/bin/env pwsh
# ONE-CLICK LAUNCHER - Starts XMRig + Dashboard automatically
# Place this on your desktop and double-click to run everything!

$ErrorActionPreference = "SilentlyContinue"

# Configuration
$XMRIG_PATH = "C:\XMRig\xmrig-6.22.0"
$XMRIG_EXE = Join-Path $XMRIG_PATH "xmrig.exe"
$DASHBOARD_PATH = Join-Path $PSScriptRoot "dashboard"
$DASHBOARD_SCRIPT = Join-Path $DASHBOARD_PATH "mining-dashboard.py"

# Load Windows Forms for message boxes
Add-Type -AssemblyName System.Windows.Forms

# Hide console window (runs silently in background)
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) | Out-Null

# Function to check if XMRig is running
function Test-XMRigRunning {
    $process = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    return $null -ne $process
}

# Function to start XMRig
function Start-XMRig {
    if (Test-Path $XMRIG_EXE) {
        Start-Process -FilePath $XMRIG_EXE -WorkingDirectory $XMRIG_PATH -WindowStyle Hidden
        Start-Sleep -Seconds 5  # Wait for XMRig to initialize
        return $true
    }
    return $false
}

# Function to start Dashboard
function Start-Dashboard {
    if (Test-Path $DASHBOARD_SCRIPT) {
        Start-Process -FilePath "pythonw.exe" `
                     -ArgumentList "`"$DASHBOARD_SCRIPT`"" `
                     -WorkingDirectory $DASHBOARD_PATH `
                     -WindowStyle Hidden
        return $true
    }
    return $false
}

# Main execution
try {
    # Check/Start XMRig
    if (-not (Test-XMRigRunning)) {
        $xmrigStarted = Start-XMRig
        if (-not $xmrigStarted) {
            [System.Windows.Forms.MessageBox]::Show(
                "XMRig not found at: $XMRIG_EXE`n`nPlease check the path in the launcher script.",
                "XMRig Mining Dashboard - Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            exit 1
        }
    }

    # Start Dashboard
    $dashboardStarted = Start-Dashboard
    if (-not $dashboardStarted) {
        [System.Windows.Forms.MessageBox]::Show(
            "Dashboard script not found at: $DASHBOARD_SCRIPT`n`nPlease check the installation.",
            "XMRig Mining Dashboard - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }

    # Success - exit silently (dashboard window will appear)
    exit 0

} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "An error occurred: $_",
        "XMRig Mining Dashboard - Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}
