<#
.SYNOPSIS
    Pre-flight guard for the nightly mining reflection.

.DESCRIPTION
    Ensures Ollama's inference server is actually LISTENING before invoking
    the reflection, then runs `python -m intelligence.advisor --reflect`.

    Fixes a silent-failure mode: Ollama's Windows tray app keeps running (and
    auto-updates itself) but the `ollama serve` backend does NOT relaunch
    after an update / reboot / sleep -- leaving nothing on port 11434. When
    that happens the advisor's LLM call gets connection-refused (WinError
    10061) and writes an empty "(model returned no output)" stub instead of a
    real reflection. This went unnoticed for 12 consecutive nights
    (2026-07-10..21) because the scheduled task still fired on time and the
    decision log kept logging -- everything LOOKED alive while the LLM half
    was dark.

    Behavior:
      * If the server is already listening -> do nothing, pass straight
        through to the reflection (the common case; near-zero overhead).
      * If it is down -> start `ollama serve` (detached, hidden) with the
        project's model store, then wait up to -WaitSeconds for the port to
        bind before continuing.
      * Either way, run the reflection and exit with ITS exit code, so the
        scheduled task's thermal-defer retry semantics (advisor exits 2 when
        the thermal gate defers) keep working unchanged.

    Isolated blast radius: touches nothing the working mining path depends on.

.PARAMETER RepoPath
    XMRig-Automation repo root (working dir for the reflection). Defaults to
    the parent of this script's folder.

.PARAMETER OllamaPort
    Port Ollama's server listens on. Default 11434.

.PARAMETER OllamaModels
    OLLAMA_MODELS store to use when starting the server. Default
    F:\Dev\ollama\models (this machine's model drive).

.PARAMETER WaitSeconds
    Max seconds to wait for the server to bind after starting it. Default 40.

.NOTES
    Called by the "XMRig Nightly Reflection" scheduled task in place of
    invoking python directly. Registers/updates via
    setup\create-reflection-scheduled-task.ps1.
#>
[CmdletBinding()]
param(
    [string]$RepoPath = (Split-Path -Parent $PSScriptRoot),
    [int]$OllamaPort = 11434,
    [string]$OllamaModels = "F:\Dev\ollama\models",
    [int]$WaitSeconds = 40
)

function Test-OllamaUp {
    param([int]$Port)
    $conn = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    return [bool]$conn
}

function Resolve-OllamaExe {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        'C:\Program Files\Ollama\ollama.exe'
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Host "[$stamp] reflection pre-flight: checking Ollama on port $OllamaPort ..."

if (Test-OllamaUp -Port $OllamaPort) {
    Write-Host "  Ollama already listening -- no action needed."
}
else {
    Write-Host "  Ollama NOT listening -- starting 'ollama serve' ..."
    $exe = Resolve-OllamaExe
    if (-not $exe) {
        Write-Warning "  Could not locate ollama.exe; running reflection anyway (it will stub if it cannot connect)."
    }
    else {
        $env:OLLAMA_MODELS = $OllamaModels
        Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 750
            if (Test-OllamaUp -Port $OllamaPort) { break }
        }
        if (Test-OllamaUp -Port $OllamaPort) {
            Write-Host "  Ollama server is now listening on $OllamaPort."
        }
        else {
            Write-Warning "  Ollama did not bind within ${WaitSeconds}s; running reflection anyway."
        }
    }
}

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { throw "python not found on PATH" }

Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] running: python -m intelligence.advisor --reflect"
Push-Location $RepoPath
try {
    & $python -m intelligence.advisor --reflect
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}

Write-Host "reflection exit code: $code"
exit $code
