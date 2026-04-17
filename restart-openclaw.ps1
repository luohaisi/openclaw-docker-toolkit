#Requires -Version 5.1
# Restart OpenClaw services in this repo (docker compose up -d).
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$composeFile = Join-Path $Root 'docker-compose.yml'
if (-not (Test-Path -LiteralPath $composeFile)) {
    Write-Host "Missing file: $composeFile" -ForegroundColor Red
    exit 1
}

Write-Host "" 
Write-Host "==> docker compose up -d" -ForegroundColor Cyan
& docker compose -f $composeFile up -d
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Restart completed." -ForegroundColor Green
Write-Host "Status: docker compose -f $composeFile ps" -ForegroundColor DarkGray
