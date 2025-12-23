@echo off
REM Simple Dashboard Launcher - Visible Console
cd /d "%~dp0\dashboard"
echo.
echo ╔═══════════════════════════════════════╗
echo ║  Starting XMRig Mining Dashboard...  ║
echo ╚═══════════════════════════════════════╝
echo.
echo If dashboard window doesn't appear:
echo  - Check taskbar for Python icon
echo  - Check other monitors
echo  - Press Alt+Tab to find window
echo.
echo Press Ctrl+C to stop the dashboard
echo.
python mining-dashboard.py
pause
