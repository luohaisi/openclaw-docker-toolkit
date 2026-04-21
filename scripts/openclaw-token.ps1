function Get-OpenClawDotEnvValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match "^\s*$Key\s*=\s*(.+)\s*$") { return $matches[1].Trim() }
    }
    return $null
}

function Save-OpenClawDotEnvUtf8Bom {
    param([string]$Path, [string[]]$Lines)
    $enc = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllLines($Path, $Lines, $enc)
}

function Set-OpenClawDotEnvValue {
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
    $newLine = "$Key=$Value"
    if ($idx -ge 0) {
        $lines[$idx] = $newLine
    } else {
        $lines += $newLine
    }
    Save-OpenClawDotEnvUtf8Bom -Path $Path -Lines $lines
}

function Get-OpenClawJsonGatewayToken {
    param([string]$JsonPath)
    if (-not (Test-Path -LiteralPath $JsonPath)) { return $null }
    $raw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
    $obj = $null
    try {
        $obj = $raw | ConvertFrom-Json
    } catch {
        Write-Host "Cannot parse JSON for token sync: $JsonPath" -ForegroundColor Yellow
        return $null
    }
    if (-not $obj.gateway -or -not $obj.gateway.auth -or -not $obj.gateway.auth.token) {
        return $null
    }
    $t = "$($obj.gateway.auth.token)".Trim()
    if (-not $t) { return $null }
    if ($t -match '^\$\{[^}]+\}$') {
        Write-Host 'gateway.auth.token is a variable placeholder; skip .env sync.' -ForegroundColor DarkGray
        return $null
    }
    return $t
}

function Sync-OpenClawGatewayToken {
    param([string]$Root)

    $envFile = Join-Path $Root '.env'
    $jsonPath = Join-Path $Root 'openclaw\openclaw.json'
    if (-not (Test-Path -LiteralPath $envFile)) { return $false }
    if (-not (Test-Path -LiteralPath $jsonPath)) { return $false }

    $tokenFromJson = Get-OpenClawJsonGatewayToken -JsonPath $jsonPath
    if (-not $tokenFromJson) {
        Write-Host 'No concrete gateway.auth.token in openclaw.json; skip .env sync.' -ForegroundColor DarkGray
        return $false
    }

    $tokenFromEnv = Get-OpenClawDotEnvValue -Path $envFile -Key 'OPENCLAW_GATEWAY_TOKEN'
    if ($tokenFromEnv -eq $tokenFromJson) {
        Write-Host 'Gateway token already in sync (.env matches openclaw.json).' -ForegroundColor DarkGray
        return $false
    }

    Set-OpenClawDotEnvValue -Path $envFile -Key 'OPENCLAW_GATEWAY_TOKEN' -Value $tokenFromJson
    Write-Host 'Synced OPENCLAW_GATEWAY_TOKEN in .env from openclaw/openclaw.json.' -ForegroundColor DarkGray
    return $true
}
