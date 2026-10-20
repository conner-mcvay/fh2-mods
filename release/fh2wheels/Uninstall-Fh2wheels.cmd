@echo off
rem Double-click to remove fh2wheels: asks for your Azimuth and game folders. Close the game first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Fh2wheels.ps1" -Uninstall %*
echo.
pause
