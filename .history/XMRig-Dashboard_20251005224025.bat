@echo off
REM XMRig Mining Dashboard - One-Click Launcher
REM Double-click to start everything!

cd /d "%~dp0"

REM Start with VBScript (silent, no console)
start "" wscript.exe "XMRig-Dashboard.vbs"

exit
