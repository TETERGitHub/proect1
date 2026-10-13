@echo off
setlocal
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
cd /d "%~dp0"
where python >nul 2>nul
if %errorlevel%==0 (
  python tools\control.py %*
  goto end
)
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 tools\control.py %*
  goto end
)
echo Python is not installed.
echo 1. Open https://www.python.org/downloads/ and install Python 3.
echo 2. On the first installer screen tick "Add python.exe to PATH".
echo 3. Run this file again.
:end
pause
