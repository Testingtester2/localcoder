@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-agent.ps1" %*
pause
