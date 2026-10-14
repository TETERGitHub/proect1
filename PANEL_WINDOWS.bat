@echo off
rem MM2 Hub key panel with windows (no console). Double-click to open.
cd /d "%~dp0"
where pythonw >nul 2>nul
if %errorlevel%==0 (
  start "" pythonw tools\control_gui.py %*
  exit /b
)
where pyw >nul 2>nul
if %errorlevel%==0 (
  start "" pyw -3 tools\control_gui.py %*
  exit /b
)
chcp 65001 >nul
echo Python is not installed.
echo 1. Open https://www.python.org/downloads/ and install Python 3 (tick "Add python.exe to PATH" and "tcl/tk").
echo 2. Run this file again.
pause
