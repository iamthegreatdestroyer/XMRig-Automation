<#
.SYNOPSIS
    Creates desktop shortcuts for XMRig mining control scripts.

.DESCRIPTION
    Creates convenient desktop shortcuts for Start Mining, Stop Mining,
    Check Status, View Logs, Monitor Performance, and Pool Dashboard.

.PARAMETER ScriptsPath
    Path to the scripts directory.

.PARAMETER XMRigPath
    Path to XMRig installation.

.EXAMPLE
    .\create-desktop-shortcuts.ps1 -ScriptsPath "C:\XMRig-Automation\scripts" -XMRigPath "C:\XMRig"

.NOTES
    Author: XMRig Automation Project
    Version: 1.0
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptsPath,
    
    [Parameter(Mandatory = $true)]
    [string]$XMRigPath
)

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Creating Desktop Shortcuts" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shell = New-Object -ComObject WScript.Shell
    $created = 0
    
    # Shortcut 1: Start Mining
    Write-Host "Creating 'Start Mining' shortcut..." -ForegroundColor Cyan
    $shortcut = $shell.CreateShortcut("$desktopPath\XMRig - Start Mining.lnk")
    $shortcut.TargetPath = Join-Path $ScriptsPath "start-mining.bat"
    $shortcut.WorkingDirectory = $XMRigPath
    $shortcut.Description = "Start XMRig Monero mining"
    $shortcut.IconLocation = "shell32.dll,137"
    $shortcut.Save()
    Write-Host "  ✓ Created" -ForegroundColor Green
    $created++
    
    # Shortcut 2: Stop Mining
    Write-Host "Creating 'Stop Mining' shortcut..." -ForegroundColor Cyan
    $shortcut = $shell.CreateShortcut("$desktopPath\XMRig - Stop Mining.lnk")
    $shortcut.TargetPath = Join-Path $ScriptsPath "stop-mining.bat"
    $shortcut.WorkingDirectory = $XMRigPath
    $shortcut.Description = "Stop XMRig Monero mining"
    $shortcut.IconLocation = "shell32.dll,131"
    $shortcut.Save()
    Write-Host "  ✓ Created" -ForegroundColor Green
    $created++
    
    # Shortcut 3: Check Status
    Write-Host "Creating 'Check Status' shortcut..." -ForegroundColor Cyan
    $shortcut = $shell.CreateShortcut("$desktopPath\XMRig - Check Status.lnk")
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $ScriptsPath 'check-status.ps1')`" -XMRigPath `"$XMRigPath`"; Read-Host 'Press Enter to exit'"
    $shortcut.WorkingDirectory = $ScriptsPath
    $shortcut.Description = "Check XMRig mining status"
    $shortcut.IconLocation = "shell32.dll,23"
    $shortcut.Save()
    Write-Host "  ✓ Created" -ForegroundColor Green
    $created++
    
    # Shortcut 4: View Logs
    Write-Host "Creating 'View Logs' shortcut..." -ForegroundColor Cyan
    $shortcut = $shell.CreateShortcut("$desktopPath\XMRig - View Logs.lnk")
    $shortcut.TargetPath = Join-Path $ScriptsPath "view-logs.bat"
    $shortcut.WorkingDirectory = $XMRigPath
    $shortcut.Description = "View XMRig mining logs"
    $shortcut.IconLocation = "shell32.dll,70"
    $shortcut.Save()
    Write-Host "  ✓ Created" -ForegroundColor Green
    $created++
    
    # Shortcut 5: Monitor Performance
    Write-Host "Creating 'Monitor Performance' shortcut..." -ForegroundColor Cyan
    $shortcut = $shell.CreateShortcut("$desktopPath\XMRig - Monitor Performance.lnk")
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $ScriptsPath 'monitor-performance.ps1')`" -XMRigPath `"$XMRigPath`""
    $shortcut.WorkingDirectory = $ScriptsPath
    $shortcut.Description = "Real-time performance monitoring"
    $shortcut.IconLocation = "shell32.dll,247"
    $shortcut.Save()
    Write-Host "  ✓ Created" -ForegroundColor Green
    $created++
    
    # Shortcut 6: Pool Dashboard (URL)
    Write-Host "Creating 'Pool Dashboard' shortcut..." -ForegroundColor Cyan
    $shortcut = $shell.CreateShortcut("$desktopPath\XMRig - Pool Dashboard.url")
    $shortcut.TargetPath = "https://xmrpool.eu/#/dashboard"
    $shortcut.Save()
    Write-Host "  ✓ Created" -ForegroundColor Green
    $created++
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✓ Created $created desktop shortcuts!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Shortcuts available on your desktop:" -ForegroundColor White
    Write-Host "  • XMRig - Start Mining" -ForegroundColor Gray
    Write-Host "  • XMRig - Stop Mining" -ForegroundColor Gray
    Write-Host "  • XMRig - Check Status" -ForegroundColor Gray
    Write-Host "  • XMRig - View Logs" -ForegroundColor Gray
    Write-Host "  • XMRig - Monitor Performance" -ForegroundColor Gray
    Write-Host "  • XMRig - Pool Dashboard" -ForegroundColor Gray
    Write-Host ""
    
    exit 0
    
}
catch {
    Write-Host ""
    Write-Host "Error creating shortcuts: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
