@echo off
REM ========================================
REM XMRig Log Viewer
REM ========================================
REM This script displays the XMRig log file
REM ========================================

TITLE XMRig Log Viewer

REM Set the XMRig installation directory
SET XMRIG_DIR=C:\XMRig

echo ========================================
echo XMRig Log Viewer
echo ========================================
echo.

REM Check if log file exists
if exist "%XMRIG_DIR%\xmrig.log" (
    echo Displaying last 100 lines of xmrig.log...
    echo Press Ctrl+C to exit.
    echo ========================================
    echo.
    
    REM Display the log file with continuous monitoring
    powershell -Command "Get-Content '%XMRIG_DIR%\xmrig.log' -Tail 100 -Wait"
) else (
    echo ERROR: Log file not found at %XMRIG_DIR%\xmrig.log
    echo.
    echo The log file will be created when XMRig starts mining.
    echo Please start mining first using start-mining.bat
    echo.
    pause
)
