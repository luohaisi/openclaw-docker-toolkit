#Requires -Version 5.1
# Open OpenClaw TUI (requires gateway container up: docker compose up -d).
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

$composeFile = Join-Path $Root 'docker-compose.yml'
if (-not (Test-Path -LiteralPath $composeFile)) {
    Write-Host "Missing: $composeFile" -ForegroundColor Red
    exit 1
}

Write-Host "Starting TUI with --deliver (replies show in terminal). See docs.openclaw.ai/web/tui" -ForegroundColor Cyan
Write-Host "Tip: start gateway first: docker compose up -d or setup-openclaw.ps1" -ForegroundColor DarkGray
Write-Host ""

& docker compose -f $composeFile run --rm -it openclaw-cli tui --deliver @args
exit $LASTEXITCODE
