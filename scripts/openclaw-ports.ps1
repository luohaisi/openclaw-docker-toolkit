# Dot-source from setup-openclaw.ps1 / restart-openclaw.ps1
# Resolves OPENCLAW_GATEWAY_PORT / OPENCLAW_BRIDGE_PORT when host ports are busy (not when compose already running).

function Get-DotEnvKey {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match "^\s*$Key\s*=\s*(.+)\s*$") { return $matches[1].Trim() }
    }
    return $null
}

function Save-DotEnvUtf8BomPorts {
    param([string]$Path, [string[]]$Lines)
    $enc = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllLines($Path, $Lines, $enc)
}

function Set-DotEnvKey {
    param([string]$Path, [string]$Key, [string]$Value)
    $lines = @()
    if (Test-Path -LiteralPath $Path) {
        $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    }
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $idx = $i
            break
        }
    }
    $lineNew = "$Key=$Value"
    if ($idx -ge 0) {
        $lines[$idx] = $lineNew
    } else {
        $lines += $lineNew
    }
    Save-DotEnvUtf8BomPorts -Path $Path -Lines $lines
}

function Test-LocalPortBound {
    param([int]$Port)
    try {
        $listen = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
        return $null -ne $listen
    } catch {
        return $false
    }
}

function Find-FirstFreeConsecutivePortPair {
    param([int]$StartGw)
    for ($g = $StartGw; $g -le 65533; $g++) {
        if (-not (Test-LocalPortBound -Port $g) -and -not (Test-LocalPortBound -Port ($g + 1))) {
            return @{ Gateway = $g; Bridge = ($g + 1) }
        }
    }
    throw "No free consecutive TCP port pair (N, N+1) found starting from $StartGw."
}

function Update-OpenClawJsonGatewayPort {
    param(
        [string]$JsonPath,
        [int]$NewGatewayPort
    )
    if (-not (Test-Path -LiteralPath $JsonPath)) { return }
    $raw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
    $obj = $null
    try {
        $obj = $raw | ConvertFrom-Json
    } catch {
        Write-Host "JSON parse failed; skipped port update in: $JsonPath" -ForegroundColor Yellow
        return
    }
    if (-not $obj.gateway) { return }
    $obj.gateway.port = $NewGatewayPort
    if ($obj.gateway.controlUi -and $obj.gateway.controlUi.allowedOrigins) {
        $origins = @()
        foreach ($o in @($obj.gateway.controlUi.allowedOrigins)) {
            $s = "$o"
            $s = $s -replace '127\.0\.0\.1:\d+', "127.0.0.1:$NewGatewayPort"
            $s = $s -replace 'localhost:\d+', "localhost:$NewGatewayPort"
            $origins += $s
        }
        $obj.gateway.controlUi.allowedOrigins = $origins
    }
    $jsonOut = $obj | ConvertTo-Json -Depth 80
    [System.IO.File]::WriteAllText($JsonPath, $jsonOut + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Invoke-OpenClawPortAutoResolve {
    param(
        [string]$Root,
        [string[]]$ComposeArguments
    )
    $envFile = Join-Path $Root '.env'
    $gwRaw = Get-DotEnvKey -Path $envFile -Key 'OPENCLAW_GATEWAY_PORT'
    $brRaw = Get-DotEnvKey -Path $envFile -Key 'OPENCLAW_BRIDGE_PORT'
    $gw = 18789
    $br = 18790
    $n = 0
    if ($gwRaw -and [int]::TryParse($gwRaw, [ref]$n) -and $n -ge 1 -and $n -le 65535) { $gw = $n }
    $n = 0
    if ($brRaw -and [int]::TryParse($brRaw, [ref]$n) -and $n -ge 1 -and $n -le 65535) { $br = $n }

    Push-Location -LiteralPath $Root
    try {
        $running = @(& docker compose @ComposeArguments ps -q --status running 2>$null | Where-Object { $_ })
    } finally {
        Pop-Location
    }
    if ($running.Count -gt 0) {
        Write-Host 'Compose services already running; port auto-adjust skipped.' -ForegroundColor DarkGray
        return @{ Changed = $false; GatewayPort = $gw; BridgePort = $br }
    }

    $gwBusy = Test-LocalPortBound -Port $gw
    $brBusy = Test-LocalPortBound -Port $br
    if (-not $gwBusy -and -not $brBusy) {
        return @{ Changed = $false; GatewayPort = $gw; BridgePort = $br }
    }

    Write-Host "Host port(s) in use (gateway $gw and/or bridge $br). Searching for free consecutive pair (N, N+1)..." -ForegroundColor Yellow
    $pair = Find-FirstFreeConsecutivePortPair -StartGw 18789
    $ng = $pair.Gateway
    $nb = $pair.Bridge

    Set-DotEnvKey -Path $envFile -Key 'OPENCLAW_GATEWAY_PORT' -Value "$ng"
    Set-DotEnvKey -Path $envFile -Key 'OPENCLAW_BRIDGE_PORT' -Value "$nb"

    $jsonPath = Join-Path $Root 'openclaw\openclaw.json'
    Update-OpenClawJsonGatewayPort -JsonPath $jsonPath -NewGatewayPort $ng

    Write-Host "Updated ports -> gateway $ng , bridge $nb (.env + openclaw/openclaw.json gateway.port / allowedOrigins)." -ForegroundColor Green

    return @{ Changed = $true; GatewayPort = $ng; BridgePort = $nb }
}
