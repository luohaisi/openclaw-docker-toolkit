@echo off
chcp 65001 >nul
cd /d "%~dp0"
title OpenClaw Docker 部署工具包
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\tools\setup-openclaw.ps1" %*
if errorlevel 1 (
    echo.
    echo 执行失败，错误代码: %ERRORLEVEL%
)
echo.
pause
