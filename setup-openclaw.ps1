#Requires -Version 5.1
param(
    [switch]$SkipPull
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

function Write-Step { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }

function Get-DotenvValue {
    param(
        [string]$Path,
        [string]$Key
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $line = (Get-Content -LiteralPath $Path | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1)
    if (-not $line) { return $null }
    return ($line -replace "^\s*$Key\s*=\s*", "").Trim()
}

function Get-FallbackImages {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $items = @()
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*#\s*OPENCLAW_IMAGE_FALLBACK(?:_\d+)?\s*=\s*(.+?)\s*$') {
            $items += $matches[1].Trim()
        } elseif ($line -match '^\s*OPENCLAW_IMAGE_FALLBACK(?:_\d+)?\s*=\s*(.+?)\s*$') {
            $items += $matches[1].Trim()
        }
    }
    return $items | Where-Object { $_ } | Select-Object -Unique
}

function Test-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host '未找到 docker 命令。请先安装并启动 Docker Desktop。' -ForegroundColor Red
        exit 1
    }
    $null = & docker compose version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'docker compose 不可用。请更新 Docker Desktop 或安装 Compose v2。' -ForegroundColor Red
        exit 1
    }
}

Write-Step '检查 Docker'
Test-DockerReady

Write-Step '创建目录 openclaw、workspace（官方挂载路径）'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $Root 'openclaw')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $Root 'workspace')

$envFile = Join-Path $Root '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Step '创建 .env（从 defaults/env.default 复制，请编辑密钥）'
    $defaultEnv = Join-Path $Root 'defaults\env.default'
    if (-not (Test-Path -LiteralPath $defaultEnv)) {
        Write-Host "缺少模板文件: $defaultEnv" -ForegroundColor Red
        exit 1
    }
    Copy-Item -LiteralPath $defaultEnv -Destination $envFile -Force
} else {
    Write-Host '已存在 .env，跳过创建。' -ForegroundColor DarkGray
}

$configFile = Join-Path $Root 'openclaw\openclaw.json5'
if (-not (Test-Path -LiteralPath $configFile)) {
    Write-Step '创建 openclaw\openclaw.json5（从 defaults 复制）'
    $defaultCfg = Join-Path $Root 'defaults\openclaw.default.json5'
    if (-not (Test-Path -LiteralPath $defaultCfg)) {
        Write-Host "缺少模板文件: $defaultCfg" -ForegroundColor Red
        exit 1
    }
    Copy-Item -LiteralPath $defaultCfg -Destination $configFile -Force
} else {
    Write-Host '已存在 openclaw\openclaw.json5，跳过创建。' -ForegroundColor DarkGray
}

if (-not $SkipPull) {
    $composeFile = Join-Path $Root 'docker-compose.yml'
    $primaryImage = Get-DotenvValue -Path $envFile -Key 'OPENCLAW_IMAGE'
    $fallbackImages = Get-FallbackImages -Path $envFile

    Write-Step '拉取镜像 (docker compose pull)'
    & docker compose -f $composeFile pull
    if ($LASTEXITCODE -ne 0 -and $fallbackImages.Count -gt 0) {
        Write-Host '主镜像拉取失败，尝试备用镜像源...' -ForegroundColor Yellow
        foreach ($img in $fallbackImages) {
            if ($img -eq $primaryImage) { continue }
            Write-Host "尝试备用源: $img" -ForegroundColor Yellow
            $env:OPENCLAW_IMAGE = $img
            & docker compose -f $composeFile pull
            if ($LASTEXITCODE -eq 0) {
                Write-Host "备用源拉取成功: $img" -ForegroundColor Green
                break
            }
        }
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Step '启动容器 (docker compose up -d)'
& docker compose -f (Join-Path $Root 'docker-compose.yml') up -d
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Step '当前状态'
& docker compose -f (Join-Path $Root 'docker-compose.yml') ps

Write-Host ''
Write-Host '完成。Control UI: http://127.0.0.1:18789/' -ForegroundColor Green
Write-Host 'Gateway 日志: docker compose logs -f openclaw-gateway' -ForegroundColor DarkGray
Write-Host 'CLI 示例: docker compose run --rm openclaw-cli dashboard --no-open' -ForegroundColor DarkGray
