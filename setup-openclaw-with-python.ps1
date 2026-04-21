#Requires -Version 5.1
param(
    [string]$ImageArchive = '',
    [string]$StandaloneUrl = 'https://github.com/indygreg/python-build-standalone/releases/download/20250409/cpython-3.12.10+20250409-x86_64_v3-unknown-linux-gnu-install_only.tar.gz',
    [switch]$SkipPythonDownload
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

function Write-Step { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }

function Test-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host 'Docker not found. Please install and start Docker Desktop.' -ForegroundColor Red
        exit 1
    }
    $null = & docker compose version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'docker compose is not available. Please update Docker Desktop.' -ForegroundColor Red
        exit 1
    }
}

function Get-PythonVersionFromStandalone {
    param([string]$PythonExe)
    $v = & $PythonExe --version 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return "$v".Trim()
}

function Get-PythonVersionFromWindowsSeed {
    param([string]$StandaloneDir)
    # Cannot run Linux python3.exe on Windows; do not pull extra images (debian) for --version.
    $bin312 = Join-Path $StandaloneDir 'bin\python3.12'
    $bin3 = Join-Path $StandaloneDir 'bin\python3'
    if (-not ((Test-Path -LiteralPath $bin312) -or (Test-Path -LiteralPath $bin3))) {
        return $null
    }
    $includeRoot = Join-Path $StandaloneDir 'include'
    if (Test-Path -LiteralPath $includeRoot) {
        $patch = Get-ChildItem -LiteralPath $includeRoot -Recurse -Filter 'patchlevel.h' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($patch) {
            $m = Select-String -LiteralPath $patch.FullName -Pattern '^\s*#\s*define\s+PY_VERSION\s+"([^"]+)"' -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($m -and $m.Matches.Count -gt 0) {
                return "Python $($m.Matches[0].Groups[1].Value) (standalone seed)"
            }
        }
    }
    return 'Python standalone seed OK (run python3 --version inside gateway container to confirm)'
}

function Invoke-DownloadFile {
    param(
        [string]$Url,
        [string]$OutFile,
        [int]$TimeoutSec
    )
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec -UseBasicParsing
        return $true
    } catch {
        return $false
    }
}

function Test-IsWindowsHost {
    if ($PSVersionTable.PSVersion.Major -ge 6 -and $null -ne (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
        return [bool]$IsWindows
    }
    return $env:OS -eq 'Windows_NT'
}

function Expand-StandaloneArchiveDocker {
    param(
        [string]$ArchivePath,
        [string]$DestinationDir
    )
    $archiveResolved = (Resolve-Path -LiteralPath $ArchivePath).Path
    $rootResolved = (Resolve-Path -LiteralPath $Root).Path
    $destNormalized = [System.IO.Path]::GetFullPath($DestinationDir)
    $rootNormalized = [System.IO.Path]::GetFullPath($Root)
    if (-not $destNormalized.StartsWith($rootNormalized, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'DestinationDir must be under repo root for Docker extract.'
    }
    $tail = $destNormalized.Substring($rootNormalized.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
    # Bind-mount to Windows cannot store many Linux symlinks (e.g. terminfo). Skip that tree; headless Python in container is fine.
    Write-Host 'Windows host: extracting with Docker (Linux tar); excluding python/share/terminfo (bind-mount symlink limits).' -ForegroundColor DarkGray
    $inner = "rm -rf /work/$tail && mkdir -p /work/$tail && tar -xzf /in.tgz -C /work/$tail --strip-components=1 --exclude=python/share/terminfo"
    & docker run --rm `
        -v "${rootResolved}:/work" `
        -v "${archiveResolved}:/in.tgz:ro" `
        alpine `
        sh -c $inner
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker tar extract failed.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $DestinationDir 'bin\python3'))) {
        throw 'Extracted content does not contain bin/python3.'
    }
}

function Expand-StandaloneArchive {
    param(
        [string]$ArchivePath,
        [string]$DestinationDir
    )

    if (Test-IsWindowsHost) {
        Expand-StandaloneArchiveDocker -ArchivePath $ArchivePath -DestinationDir $DestinationDir
        return
    }

    if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
        throw 'tar command not found. Cannot extract standalone archive.'
    }

    $tmpExtract = Join-Path ([System.IO.Path]::GetTempPath()) ('openclaw-python-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $tmpExtract -Force
    try {
        & tar -xzf $ArchivePath -C $tmpExtract
        if ($LASTEXITCODE -ne 0) {
            throw 'tar extract failed.'
        }

        $children = @(Get-ChildItem -LiteralPath $tmpExtract -Force)
        if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
            $sourceDir = $children[0].FullName
        } else {
            $sourceDir = $tmpExtract
        }

        if (-not (Test-Path -LiteralPath (Join-Path $sourceDir 'bin\python3'))) {
            throw 'Extracted content does not contain bin/python3.'
        }

        if (Test-Path -LiteralPath $DestinationDir) {
            Remove-Item -LiteralPath $DestinationDir -Recurse -Force
        }
        $null = New-Item -ItemType Directory -Path $DestinationDir -Force
        Copy-Item -LiteralPath (Join-Path $sourceDir '*') -Destination $DestinationDir -Recurse -Force
    } finally {
        if (Test-Path -LiteralPath $tmpExtract) {
            Remove-Item -LiteralPath $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Ensure-PipConf {
    param([string]$StandaloneDir)
    $etcDir = Join-Path $StandaloneDir 'etc'
    $null = New-Item -ItemType Directory -Path $etcDir -Force
    $pipConfPath = Join-Path $etcDir 'pip.conf'
@'
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
'@ | Set-Content -LiteralPath $pipConfPath -Encoding UTF8
}

Write-Step 'Check Docker'
Test-DockerReady

$standaloneDir = Join-Path $Root 'python-standalone'
$standalonePython = Join-Path $standaloneDir 'bin\python3'
$needInstall = -not (Test-Path -LiteralPath $standalonePython)

if ($needInstall) {
    if ($SkipPythonDownload) {
        Write-Host 'python-standalone is missing and -SkipPythonDownload was set.' -ForegroundColor Red
        exit 1
    }

    Write-Step 'Download standalone Python'
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) ('python-standalone-' + [Guid]::NewGuid().ToString('N') + '.tar.gz')
    try {
        Write-Host "Downloading: $StandaloneUrl" -ForegroundColor DarkGray
        $ok = Invoke-DownloadFile -Url $StandaloneUrl -OutFile $archivePath -TimeoutSec 600
        if (-not $ok) {
            Write-Host 'Download failed. Use -StandaloneUrl to point to a mirror, or download the archive manually.' -ForegroundColor Red
            exit 1
        }

        Write-Step 'Extract standalone Python into python-standalone'
        Expand-StandaloneArchive -ArchivePath $archivePath -DestinationDir $standaloneDir
    } finally {
        if (Test-Path -LiteralPath $archivePath) {
            Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host 'python-standalone already exists, skip download.' -ForegroundColor DarkGray
}

Ensure-PipConf -StandaloneDir $standaloneDir

if (Test-IsWindowsHost) {
    $ver = Get-PythonVersionFromWindowsSeed -StandaloneDir $standaloneDir
} else {
    $ver = Get-PythonVersionFromStandalone -PythonExe $standalonePython
}
if (-not $ver) {
    Write-Host 'Standalone Python verification failed: seed layout looks wrong (missing bin/python3.12 or bin/python3).' -ForegroundColor Red
    exit 1
}
Write-Host "Standalone Python is ready: $ver" -ForegroundColor Green

Write-Step 'Run base setup script (offline image + env + config)'
$setupScript = Join-Path $Root 'setup-openclaw.ps1'
if (-not (Test-Path -LiteralPath $setupScript)) {
    Write-Host "Missing script: $setupScript" -ForegroundColor Red
    exit 1
}
if ($ImageArchive) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $setupScript -ImageArchive $ImageArchive -SkipComposeUp
} else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $setupScript -SkipComposeUp
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Step 'Start stack (base + Python overlay in one compose up)'
$portsScript = Join-Path $Root 'scripts\openclaw-ports.ps1'
$y1 = Join-Path $Root 'docker-compose.yml'
$y2 = Join-Path $Root 'docker-compose.python.yml'
if (Test-Path -LiteralPath $portsScript) {
    . $portsScript
    $null = Invoke-OpenClawPortAutoResolve -Root $Root -ComposeArguments @('-f', $y1, '-f', $y2)
}
# Single up with both files avoids: openclaw-cli (network_mode: service:gateway) joining while gateway is mid-recreate (two-step force-recreate race).
& docker compose -f $y1 -f $y2 up -d
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Step 'Status'
& docker compose -f docker-compose.yml -f docker-compose.python.yml ps

Write-Host ''
Write-Host 'Done. Standalone Python mode is enabled (read-only seed + writable volume).' -ForegroundColor Green
Write-Host 'First start copies into /opt/python, next starts will reuse it.' -ForegroundColor DarkGray
Write-Host 'Logs: docker compose -f docker-compose.yml -f docker-compose.python.yml logs -f openclaw-gateway' -ForegroundColor DarkGray
Write-Host 'Verify: docker compose -f docker-compose.yml -f docker-compose.python.yml exec openclaw-gateway python3 --version' -ForegroundColor DarkGray
