@echo off
rem Double-click to install fh2wheels (or update it): asks for your Azimuth folder. Close the game first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Fh2wheels.ps1" %*
echo.
pause
