#Requires -Version 5.1
param(
    [string]$ImageArchive = '',
    [ValidateSet('auto', 'with-python', 'without-python')]
    [string]$Mode = 'auto'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location -LiteralPath $Root

function Resolve-SetupMode {
    param([string]$Requested)
    if ($Requested -ne 'auto') { return $Requested }
    if (-not [Environment]::UserInteractive) {
        Write-Host 'Non-interactive session detected; defaulting to with-python.' -ForegroundColor DarkGray
        return 'with-python'
    }

    Write-Host ''
    Write-Host 'Choose setup mode:' -ForegroundColor Cyan
    Write-Host '  [Y] with-python (default in 10s)' -ForegroundColor Cyan
    Write-Host '  [N] without-python' -ForegroundColor Cyan
    & cmd /c "choice /C YN /N /T 10 /D Y /M ""Select mode [Y/N]"""
    if ($LASTEXITCODE -eq 2) { return 'without-python' }
    return 'with-python'
}

$selectedMode = Resolve-SetupMode -Requested $Mode

if ($selectedMode -eq 'with-python') {
    $scriptPath = Join-Path $Root 'setup-openclaw-with-python.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Host "Missing script: $scriptPath" -ForegroundColor Red
        exit 1
    }
    if ($ImageArchive) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ImageArchive $ImageArchive
    } else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    }
    exit $LASTEXITCODE
}

$baseScript = Join-Path $Root 'setup-openclaw.ps1'
if (-not (Test-Path -LiteralPath $baseScript)) {
    Write-Host "Missing script: $baseScript" -ForegroundColor Red
    exit 1
}
if ($ImageArchive) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $baseScript -ImageArchive $ImageArchive
} else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $baseScript
}
exit $LASTEXITCODE
