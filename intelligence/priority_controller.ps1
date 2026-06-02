# ============================================================================
# ADAPTIVE PRIORITY CONTROLLER
# ============================================================================
# Dynamically adjusts XMRig process priority based on user idle time.
# Never pauses/restarts XMRig (avoids 30s RandomX re-initialization penalty).
#
# Priority schedule:
#   User active  (<5 min idle)  → BelowNormal  — yields to user apps
#   User idle    (5-30 min)     → Normal        — standard priority
#   User away    (>30 min)      → AboveNormal   — maximum hash throughput
#
# Usage:
#   PowerShell -ExecutionPolicy Bypass -File priority_controller.ps1
#   Add -Silent for background operation with no console output
# ============================================================================

param(
    [int]$CheckIntervalSeconds = 30,
    [switch]$Silent
)

$LogFile = "C:\XMRig\logs\priority-controller.log"

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class UserActivity {
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    public static double GetIdleMinutes() {
        var info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        GetLastInputInfo(ref info);
        uint idleMs = (uint)Environment.TickCount - info.dwTime;
        return idleMs / 60000.0;
    }
}
"@

function Write-Log {
    param([string]$Msg, [string]$Color = "Cyan")
    $ts = Get-Date -Format "HH:mm:ss"
    $entry = "[$ts] $Msg"
    if (-not $Silent) { Write-Host $entry -ForegroundColor $Color }
    try {
        $dir = Split-Path $LogFile
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
    } catch {}
}

function Set-XMRigPriority {
    param([string]$Priority)
    $proc = Get-Process "xmrig" -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }
    try {
        $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::$Priority
        return $true
    } catch {
        Write-Log "Failed to set priority: $($_.Exception.Message)" "Red"
        return $false
    }
}

$lastPriority = ""

Write-Log "Adaptive Priority Controller started. Check interval: ${CheckIntervalSeconds}s" "Green"

while ($true) {
    $idleMin = [UserActivity]::GetIdleMinutes()
    $xmrig = Get-Process "xmrig" -ErrorAction SilentlyContinue

    if (-not $xmrig) {
        Write-Log "XMRig not running. Waiting..." "Yellow"
        Start-Sleep -Seconds $CheckIntervalSeconds
        continue
    }

    $targetPriority = switch ($true) {
        ($idleMin -lt 5)  { "BelowNormal" }
        ($idleMin -lt 30) { "Normal" }
        default           { "AboveNormal" }
    }

    if ($targetPriority -ne $lastPriority) {
        $ok = Set-XMRigPriority -Priority $targetPriority
        if ($ok) {
            $emoji = switch ($targetPriority) {
                "AboveNormal" { "FULL POWER" }
                "Normal"      { "NORMAL" }
                "BelowNormal" { "YIELDING" }
            }
            Write-Log "Priority → $targetPriority [$emoji] (idle: $([math]::Round($idleMin,1)) min)" "Green"
            $lastPriority = $targetPriority
        }
    }

    Start-Sleep -Seconds $CheckIntervalSeconds
}
