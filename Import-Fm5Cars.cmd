@echo off
rem Double-click to import FM5 cars into FH2: asks for your folders and the cars you want.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Import-Fm5Cars.ps1" %*
echo.
pause
