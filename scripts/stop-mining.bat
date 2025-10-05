@echo off
REM ========================================
REM XMRig Stop Mining Script
REM ========================================
REM This script gracefully stops XMRig mining
REM ========================================

TITLE Stop XMRig Mining

REM Set the XMRig installation directory
SET XMRIG_DIR=C:\XMRig

REM Log file
SET RESTART_LOG=%XMRIG_DIR%\logs\restart-log.txt

echo ========================================
echo Stopping XMRig Mining...
echo ========================================
echo.

REM Check if XMRig process is running
tasklist /FI "IMAGENAME eq xmrig.exe" 2>NUL | find /I /N "xmrig.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo XMRig is running. Stopping process...
    
    REM Kill the XMRig process
    taskkill /F /IM xmrig.exe >NUL 2>&1
    
    REM Wait a moment for process to terminate
    timeout /t 2 /nobreak >NUL
    
    REM Verify it stopped
    tasklist /FI "IMAGENAME eq xmrig.exe" 2>NUL | find /I /N "xmrig.exe">NUL
    if "%ERRORLEVEL%"=="1" (
        echo [SUCCESS] XMRig mining stopped successfully!
        echo [%date% %time%] Mining stopped manually >> "%RESTART_LOG%"
    ) else (
        echo [WARNING] XMRig may still be running. Please check Task Manager.
        echo [%date% %time%] Stop command issued but process may still be running >> "%RESTART_LOG%"
    )
) else (
    echo XMRig is not currently running.
    echo [%date% %time%] Stop command issued but XMRig was not running >> "%RESTART_LOG%"
)

echo.
echo ========================================
echo Operation complete.
echo ========================================
echo.

timeout /t 5
