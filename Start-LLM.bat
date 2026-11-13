@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-llm.ps1" %*
pause
