[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [int]$Top = 10,
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [string]$OutDir = '.\\output',
    [switch]$IncludeExpansions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\\Invoke-BggMcp.ps1"

if ($Top -lt 1) {
    throw 'Top must be at least 1.'
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$toolArgs = @{
    username = $Username
    rated = $true
    owned = $true
    minrating = 1
}

if (-not $IncludeExpansions) {
    $toolArgs.subtype = 'boardgame'
}

$result = Invoke-BggMcpTool -ToolName 'bgg-collection' -Arguments $toolArgs -Endpoint $Endpoint -Username $Username -ApiKey $ApiKey -Cookie $Cookie

$items = @($result)

if (-not $items -or $items.Count -eq 0) {
    Write-Warning 'No rated games found.'
    return
}

$script:i = 0

$ranked = $items |
    Where-Object { [double]($_.rating ?? 0) -gt 0 } |
    Sort-Object @{ Expression = { [double]($_.rating ?? 0) }; Descending = $true },
                @{ Expression = { [int]($_.numplays ?? 0) }; Descending = $true },
                @{ Expression = { $_.name } } |
    Select-Object -First $Top |
    Select-Object @{ Name = 'rank'; Expression = { $script:i = ($script:i + 1); $script:i } },
                  @{ Name = 'bgg_id'; Expression = { $_.objectid } },
                  @{ Name = 'name'; Expression = { $_.name } },
                  @{ Name = 'year_published'; Expression = { $_.yearpublished } },
                  @{ Name = 'rating'; Expression = { [double]($_.rating ?? 0) } },
                  @{ Name = 'num_plays'; Expression = { [int]($_.numplays ?? 0) } }

$jsonPath = Join-Path $OutDir 'top-games.json'
$csvPath = Join-Path $OutDir 'top-games.csv'

$ranked | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
$ranked | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$ranked

[pscustomobject]@{
    TopCount = $ranked.Count
    Json = $jsonPath
    Csv = $csvPath
}
