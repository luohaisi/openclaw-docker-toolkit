#Requires -Version 5.1
# Local OSS upload test (ossutil v1.7.18 windows-amd64).
# Copy scripts/oss-local.env.example -> scripts/oss-local.env (OSS_ENDPOINT, OSS_BUCKET).
# Set OSS_ACCESS_KEY_ID and OSS_ACCESS_KEY_SECRET in environment (not in oss-local.env).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-oss-upload.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Get-EnvFirst {
    param([string]$Name)
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $v = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
    }
    return $null
}

$localEnvFile = Join-Path $Root 'scripts\oss-local.env'
if (-not (Test-Path -LiteralPath $localEnvFile)) {
    Write-Host 'Missing scripts/oss-local.env. Copy scripts/oss-local.env.example and set OSS_ENDPOINT and OSS_BUCKET.' -ForegroundColor Red
    exit 1
}

Get-Content -LiteralPath $localEnvFile | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { return }
    $key = $line.Substring(0, $idx).Trim()
    $val = $line.Substring($idx + 1).Trim()
    if ($key -match '^(OSS_ENDPOINT|OSS_BUCKET)$') {
        Set-Item -Path "Env:$key" -Value $val
    }
}

if ([string]::IsNullOrWhiteSpace($env:OSS_ENDPOINT) -or [string]::IsNullOrWhiteSpace($env:OSS_BUCKET)) {
    Write-Host 'Fill OSS_ENDPOINT and OSS_BUCKET in scripts/oss-local.env.' -ForegroundColor Red
    exit 1
}

foreach ($k in @('OSS_ACCESS_KEY_ID', 'OSS_ACCESS_KEY_SECRET')) {
    if ($null -eq (Get-EnvFirst -Name $k)) {
        Write-Host "Missing env var: $k (set User or Process; do not put secrets in oss-local.env)." -ForegroundColor Red
        exit 1
    }
}

$ak = Get-EnvFirst -Name 'OSS_ACCESS_KEY_ID'
$sk = Get-EnvFirst -Name 'OSS_ACCESS_KEY_SECRET'

$ver = 'v1.7.18'
$url = "https://github.com/aliyun/ossutil/releases/download/$ver/ossutil-$ver-windows-amd64.zip"
$zip = Join-Path $env:TEMP "ossutil-$ver-windows-amd64.zip"
$dest = Join-Path $env:TEMP "ossutil-$ver-win"
Write-Host "Downloading ossutil: $url" -ForegroundColor Cyan
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
$exe = Get-ChildItem -Path $dest -Recurse -Filter 'ossutil.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) {
    Write-Host 'ossutil.exe not found after unzip.' -ForegroundColor Red
    exit 1
}

$testFile = Join-Path $Root 'scripts\.oss-test-upload.txt'
"openclaw-docker-toolkit oss test $(Get-Date -Format o)" | Set-Content -LiteralPath $testFile -Encoding UTF8
$objectKey = 'docker-images/oss-connection-test.txt'

& $exe.FullName config -e $env:OSS_ENDPOINT -i $ak -k $sk
& $exe.FullName cp $testFile "oss://$($env:OSS_BUCKET)/$objectKey"
Write-Host "OK: oss://$($env:OSS_BUCKET)/$objectKey" -ForegroundColor Green
Write-Host 'If the bucket is private, the HTTPS URL below may return 403; check the object in OSS console.' -ForegroundColor DarkGray
Write-Host "https://$($env:OSS_BUCKET).$($env:OSS_ENDPOINT)/$objectKey"
