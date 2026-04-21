@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Restart OpenClaw (docker compose up -d)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\tools\restart-openclaw.ps1" %*
if errorlevel 1 (
    echo.
    echo 执行失败，错误代码: %ERRORLEVEL%
)
echo.
pause
