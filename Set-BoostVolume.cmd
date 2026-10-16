@echo off
rem Double-click to make cars' turbo and supercharger sounds louder or quieter: asks for the cars and the dB.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\audio\Set-BoostVolume.ps1" %*
echo.
pause
