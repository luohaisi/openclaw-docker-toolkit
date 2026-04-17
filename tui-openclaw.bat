@echo off
chcp 65001 >nul
cd /d "%~dp0"
title OpenClaw TUI
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tui-openclaw.ps1" %*
set EXITCODE=%ERRORLEVEL%
if not "%EXITCODE%"=="0" (
    echo.
    echo Exit code: %EXITCODE%
)
pause
