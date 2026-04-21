#Requires -Version 5.1
param(
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
    if (Test-Path -LiteralPath (Join-Path $Root 'python-standalone')) { return $true }
    try {
        $vols = @(& docker volume ls --format '{{.Name}}' 2>$null)
        return ($vols -contains 'openclaw-docker_openclaw-python')
    } catch {
        return $false
    }
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

$portsScript = Join-Path $Root 'scripts\openclaw-ports.ps1'
if (Test-Path -LiteralPath $portsScript) {
    . $portsScript
    $null = Invoke-OpenClawPortAutoResolve -Root $Root -ComposeArguments $composeArgs
}
$tokenSyncScript = Join-Path $Root 'scripts\openclaw-token.ps1'
if (Test-Path -LiteralPath $tokenSyncScript) {
    . $tokenSyncScript
    $null = Sync-OpenClawGatewayToken -Root $Root
}

Write-Host ''
if ($usePython) {
    Write-Host '==> docker compose up -d (auto: with python)' -ForegroundColor Cyan
} else {
    Write-Host '==> docker compose up -d (auto: without python)' -ForegroundColor Cyan
}
& docker compose @composeArgs up -d
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host 'Restart completed.' -ForegroundColor Green
