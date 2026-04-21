@echo off
chcp 65001 >nul
cd /d "%~dp0"
title 停止 OpenClaw (Docker Compose)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\tools\stop-openclaw.ps1" %*
if errorlevel 1 (
    echo.
    echo 执行失败，错误代码: %ERRORLEVEL%
)
echo.
pause
