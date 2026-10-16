@echo off
rem Double-click for sliders that tune a car's sound (exhaust, engine, intake, turbo, superchargers, ...).
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0tools\audio\Tune-CarSound.ps1" %*
