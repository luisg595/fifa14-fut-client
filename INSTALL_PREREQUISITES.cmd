@echo off
setlocal
cd /d "%~dp0"
title FIFA 14 FUT Client - Install Prerequisites
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\install_prerequisites.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo PREREQUISITES FAILED. Read the error above.
) else (
  echo PREREQUISITES COMPLETE. You can now run INSTALL_GAME_PATCHES.cmd and RUN_REMOTE_FUT.cmd.
)
pause
exit /b %RC%