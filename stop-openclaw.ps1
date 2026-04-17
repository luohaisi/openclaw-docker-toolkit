#Requires -Version 5.1
# Stops OpenClaw containers from this repo (does not quit Docker Desktop).
param(
    [switch]$RemoveVolumes
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$composeFile = Join-Path $Root 'docker-compose.yml'
if (-not (Test-Path -LiteralPath $composeFile)) {
    Write-Host "Missing file: $composeFile" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==> docker compose down" -ForegroundColor Cyan
$argsDown = @('-f', $composeFile, 'down')
if ($RemoveVolumes) {
    $argsDown += '-v'
    Write-Host '-RemoveVolumes: also removes compose volumes.' -ForegroundColor Yellow
}

& docker compose @argsDown
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Stopped. Data remains in openclaw/, workspace/ and .env." -ForegroundColor Green
Write-Host "Start again: .\setup-openclaw.ps1 or docker compose up -d" -ForegroundColor Green
Write-Host "To quit Docker Desktop (all engines): tray icon, right-click, Quit Docker Desktop." -ForegroundColor DarkGray
