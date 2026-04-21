#Requires -Version 5.1
param(
    [switch]$RemoveVolumes,
    [ValidateSet('auto', 'with-python', 'without-python')]
    [string]$Mode = 'auto'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location -LiteralPath $Root

function Test-UsePythonMode {
    param([string]$Requested)
    if ($Requested -eq 'with-python') { return $true }
    if ($Requested -eq 'without-python') { return $false }
    $yml2 = Join-Path $Root 'docker-compose.python.yml'
    if (-not (Test-Path -LiteralPath $yml2)) { return $false }
    try {
        $running = @(& docker compose -f (Join-Path $Root 'docker-compose.yml') -f $yml2 ps -q --status running 2>$null | Where-Object { $_ })
        if ($running.Count -gt 0) { return $true }
    } catch {}
    if (Test-Path -LiteralPath (Join-Path $Root 'python-standalone')) { return $true }
    return $false
}

$yml1 = Join-Path $Root 'docker-compose.yml'
if (-not (Test-Path -LiteralPath $yml1)) {
    Write-Host "Missing docker-compose.yml under: $Root" -ForegroundColor Red
    exit 1
}
$usePython = Test-UsePythonMode -Requested $Mode

$composeArgs = @('-f', $yml1)
if ($usePython) {
    $yml2 = Join-Path $Root 'docker-compose.python.yml'
    if (-not (Test-Path -LiteralPath $yml2)) {
        Write-Host "Missing docker-compose.python.yml under: $Root" -ForegroundColor Red
        exit 1
    }
    $composeArgs += @('-f', $yml2)
}

$argsDown = @('down')
if ($RemoveVolumes) { $argsDown += '-v' }

Write-Host ''
if ($usePython) {
    Write-Host '==> docker compose down (auto: with python)' -ForegroundColor Cyan
} else {
    Write-Host '==> docker compose down (auto: without python)' -ForegroundColor Cyan
}
& docker compose @composeArgs @argsDown
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host 'Stopped.' -ForegroundColor Green
