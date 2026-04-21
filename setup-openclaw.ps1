#Requires -Version 5.1
# 仅使用本地离线包（.tar.gz / .tar），不执行 docker pull。
param(
    [string]$ImageArchive = '',
    # Used by setup-openclaw-with-python.ps1: prepare image/env/config but do not start; caller runs compose with python overlay in one shot (avoids openclaw-cli network_mode race).
    [switch]$SkipComposeUp
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

function Write-Step { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }

function Test-IsGzipTar {
    param([string]$Path)
    $n = $Path.ToLowerInvariant()
    return $n.EndsWith('.tar.gz') -or $n.EndsWith('.tgz')
}

function Invoke-DockerLoadFromArchive {
    param([string]$ArchivePath)
    $resolved = Resolve-Path -LiteralPath $ArchivePath -ErrorAction Stop
    $fullName = $resolved.Path
    $tmpTar = $null
    try {
        if (Test-IsGzipTar -Path $fullName) {
            $tmpTar = Join-Path ([System.IO.Path]::GetTempPath()) ('openclaw-load-' + [Guid]::NewGuid().ToString('N') + '.tar')
            $inStream = [System.IO.File]::OpenRead($fullName)
            try {
                $gzip = New-Object System.IO.Compression.GZipStream($inStream, [System.IO.Compression.CompressionMode]::Decompress)
                try {
                    $outStream = [System.IO.File]::Create($tmpTar)
                    try { $gzip.CopyTo($outStream) } finally { $outStream.Dispose() }
                } finally { $gzip.Dispose() }
            } finally { $inStream.Dispose() }
            $loadPath = $tmpTar
        } elseif ($fullName.ToLowerInvariant().EndsWith('.tar')) {
            $loadPath = $fullName
        } else {
            throw "不支持的格式（请使用 .tar.gz / .tgz / .tar）: $ArchivePath"
        }
        $raw = & docker load -i $loadPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            $raw | ForEach-Object { Write-Host $_ }
            throw 'docker load 失败'
        }
        foreach ($line in @($raw)) {
            $s = "$line"
            if ($s -match 'Loaded image:\s*(.+)\s*$') { return $matches[1].Trim() }
            if ($s -match '已加载镜像:\s*(.+)\s*$') { return $matches[1].Trim() }
        }
        $txt = ($raw | Out-String).Trim()
        if ($txt -match 'Loaded image:\s*(.+)') { return $matches[1].Trim() }
        return $null
    } finally {
        if ($tmpTar -and (Test-Path -LiteralPath $tmpTar)) {
            Remove-Item -LiteralPath $tmpTar -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host '未找到 docker。请先安装并启动 Docker Desktop。' -ForegroundColor Red
        exit 1
    }
    $null = & docker compose version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'docker compose 不可用。请更新 Docker Desktop。' -ForegroundColor Red
        exit 1
    }
}

function Get-DotenvValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match "^\s*$Key\s*=\s*(.+)\s*$") { return $matches[1].Trim() }
    }
    return $null
}

function Save-DotEnvUtf8Bom {
    param([string]$Path, [string[]]$Lines)
    $enc = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllLines($Path, $lines, $enc)
}

function Repair-DotEnvFileEncoding {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = @()
    try {
        $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    } catch {
        $lines = @(Get-Content -LiteralPath $Path)
    }
    Save-DotEnvUtf8Bom -Path $Path -Lines $lines
}

function Get-GatewayPort {
    param([string]$EnvPath)
    $raw = Get-DotenvValue -Path $EnvPath -Key 'OPENCLAW_GATEWAY_PORT'
    if ($raw) {
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le 65535) { return $n }
    }
    return 18789
}

function New-OpenClawGatewayToken {
    # 仅 [A-Za-z0-9-]，避免 Base64 的 +/= 在 shell、复制、部分工具中被截断或误解析
    $alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-'
    $alphabetLen = $alphabet.Length
    $len = 48
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] $len
        $rng.GetBytes($bytes)
        $sb = New-Object System.Text.StringBuilder $len
        for ($i = 0; $i -lt $len; $i++) {
            [void]$sb.Append($alphabet[[int]($bytes[$i] % $alphabetLen)])
        }
        return $sb.ToString()
    } finally {
        if ($rng -is [System.IDisposable]) { $rng.Dispose() }
    }
}

function Set-EnvGatewayTokenIfMissing {
    param([string]$EnvPath)
    if (-not (Test-Path -LiteralPath $EnvPath)) { return $null }
    $lines = @(Get-Content -LiteralPath $EnvPath -Encoding UTF8)
    $tokenIdx = -1
    $hasNonEmpty = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*OPENCLAW_GATEWAY_TOKEN\s*=\s*(.*)$') {
            if ($matches[1].Trim().Length -gt 0) { $hasNonEmpty = $true }
            $tokenIdx = $i
            break
        }
        if ($line -match '^\s*#\s*OPENCLAW_GATEWAY_TOKEN\s*=') {
            $tokenIdx = $i
            break
        }
    }
    if ($hasNonEmpty) { return $null }
    $token = New-OpenClawGatewayToken
    if ($tokenIdx -ge 0) {
        $lines[$tokenIdx] = "OPENCLAW_GATEWAY_TOKEN=$token"
    } else {
        $lines += "OPENCLAW_GATEWAY_TOKEN=$token"
    }
    Save-DotEnvUtf8Bom -Path $EnvPath -Lines $lines
    return $token
}

Write-Step '检查 Docker'
Test-DockerReady

$archive = $ImageArchive
if (-not $archive) {
    foreach ($c in @((Join-Path $Root 'images\openclaw.tar.gz'), (Join-Path $Root 'openclaw.tar.gz'))) {
        if (Test-Path -LiteralPath $c) { $archive = $c; break }
    }
}
if (-not $archive -or -not (Test-Path -LiteralPath $archive)) {
    Write-Host '请先把离线镜像放到下列路径之一，或传 -ImageArchive 指定文件：' -ForegroundColor Red
    Write-Host "  $(Join-Path $Root 'images\openclaw.tar.gz')" -ForegroundColor Yellow
    Write-Host "  $(Join-Path $Root 'openclaw.tar.gz')" -ForegroundColor Yellow
    Write-Host '  .\setup-openclaw.ps1 -ImageArchive "D:\路径\openclaw-xxx.tar.gz"' -ForegroundColor Yellow
    exit 1
}

Write-Step "加载镜像: $archive"
$loadedRef = Invoke-DockerLoadFromArchive -ArchivePath $archive
if ($loadedRef) {
    $env:OPENCLAW_IMAGE = $loadedRef
    Write-Host "已加载: $loadedRef" -ForegroundColor Green
    Write-Host '请把 .env 里 OPENCLAW_IMAGE 改成上面这一行，以后直接 docker compose up 才一致。' -ForegroundColor DarkGray
}

Write-Step '创建目录 openclaw、workspace'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $Root 'openclaw')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $Root 'workspace')

$envFile = Join-Path $Root '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Step '创建 .env（从 defaults 复制）'
    $defaultEnv = Join-Path $Root 'defaults\env.default'
    if (-not (Test-Path -LiteralPath $defaultEnv)) {
        Write-Host "缺少: $defaultEnv" -ForegroundColor Red
        exit 1
    }
    Copy-Item -LiteralPath $defaultEnv -Destination $envFile -Force
    Repair-DotEnvFileEncoding -Path $envFile
} else {
    Write-Host '已存在 .env。' -ForegroundColor DarkGray
    Repair-DotEnvFileEncoding -Path $envFile
}

$newToken = Set-EnvGatewayTokenIfMissing -EnvPath $envFile
if ($newToken) {
    Write-Step '已生成 OPENCLAW_GATEWAY_TOKEN（写入 .env）'
    Write-Host 'Control UI 登录时请粘贴下方 Token（仅此一次显示，勿发给他人）：' -ForegroundColor Yellow
    Write-Host $newToken -ForegroundColor Green
    Write-Host '若关闭窗口后忘记，请打开 .env 查看 OPENCLAW_GATEWAY_TOKEN。' -ForegroundColor DarkGray
}

$configFile = Join-Path $Root 'openclaw\openclaw.json'
if (-not (Test-Path -LiteralPath $configFile)) {
    Write-Step '创建 openclaw\openclaw.json'
    $defaultCfg = Join-Path $Root 'defaults\openclaw.default.json'
    if (-not (Test-Path -LiteralPath $defaultCfg)) {
        Write-Host "缺少: $defaultCfg" -ForegroundColor Red
        exit 1
    }
    Copy-Item -LiteralPath $defaultCfg -Destination $configFile -Force
} else {
    Write-Host '已存在 openclaw\openclaw.json，跳过。' -ForegroundColor DarkGray
}

$tokenSyncScript = Join-Path $Root 'scripts\openclaw-token.ps1'
if (Test-Path -LiteralPath $tokenSyncScript) {
    . $tokenSyncScript
    $null = Sync-OpenClawGatewayToken -Root $Root
}

$composeFile = Join-Path $Root 'docker-compose.yml'
$gwPort = Get-GatewayPort -EnvPath $envFile
$portsScript = Join-Path $Root 'scripts\openclaw-ports.ps1'
if (Test-Path -LiteralPath $portsScript) {
    . $portsScript
    $portResult = Invoke-OpenClawPortAutoResolve -Root $Root -ComposeArguments @('-f', $composeFile)
    if ($null -ne $portResult -and $null -ne $portResult.GatewayPort) {
        $gwPort = $portResult.GatewayPort
    }
}

if (-not $SkipComposeUp) {
    Write-Step '启动容器'
    & docker compose -f $composeFile up -d
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Step '状态'
    & docker compose -f $composeFile ps

    Write-Host ''
    Write-Host "完成。Control UI: http://127.0.0.1:${gwPort}/" -ForegroundColor Green
    Write-Host '日志: docker compose logs -f openclaw-gateway' -ForegroundColor DarkGray
    Write-Host '说明: 容器由 Docker 在后台运行，关掉本窗口不会停止服务；停止请执行: docker compose down（或退出 Docker Desktop）。' -ForegroundColor DarkGray
} else {
    Write-Host 'SkipComposeUp: 已跳过 docker compose up，由调用方用叠加编排一次性启动。' -ForegroundColor DarkGray
}
