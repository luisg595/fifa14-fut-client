@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\install_fifa14_game_patches.ps1"
echo.
pause
