@echo off
REM ========================================
REM XMRig Auto-Restart Mining Script
REM ========================================
REM This script starts XMRig and automatically
REM restarts it if it crashes or stops.
REM ========================================

TITLE XMRig Monero Miner - RyzenRig

REM Set the XMRig installation directory
REM This will be configured during setup
SET XMRIG_DIR=C:\XMRig

REM Create logs directory if it doesn't exist
if not exist "%XMRIG_DIR%\logs" mkdir "%XMRIG_DIR%\logs"

REM Log file for restart events
SET RESTART_LOG=%XMRIG_DIR%\logs\restart-log.txt

echo ========================================
echo XMRig Monero Miner - Auto Restart
echo ========================================
echo Rig ID: RyzenRig
echo Pool: xmrpool.eu:3333
echo ========================================
echo.
echo Starting mining... Press Ctrl+C to stop.
echo.

REM Log the initial start
echo [%date% %time%] Mining started >> "%RESTART_LOG%"

:RESTART_LOOP
REM Change to XMRig directory
cd /d "%XMRIG_DIR%"

REM Check if xmrig.exe exists
if not exist "%XMRIG_DIR%\xmrig.exe" (
    echo ERROR: xmrig.exe not found in %XMRIG_DIR%
    echo Please ensure XMRig is installed correctly.
    echo [%date% %time%] ERROR: xmrig.exe not found >> "%RESTART_LOG%"
    pause
    exit /b 1
)

REM Start XMRig
echo [%date% %time%] Starting XMRig...
"%XMRIG_DIR%\xmrig.exe" --config=config.json

REM If we reach here, XMRig has stopped
echo.
echo ========================================
echo XMRig stopped. Restarting in 10 seconds...
echo Press Ctrl+C to cancel restart.
echo ========================================
echo.

REM Log the restart event
echo [%date% %time%] XMRig stopped - restarting in 10 seconds >> "%RESTART_LOG%"

REM Wait 10 seconds before restarting
timeout /t 10 /nobreak

REM Loop back to restart
goto RESTART_LOOP
