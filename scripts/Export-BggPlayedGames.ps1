[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [string]$OutDir = '.\\output',
    [switch]$IncludeExpansions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\\Invoke-BggMcp.ps1"

function Get-CollectionValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Item,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [object]$DefaultValue = 0
    )

    $property = $Item.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value -or $property.Value -eq '') {
        return $DefaultValue
    }

    return $property.Value
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$toolArgs = @{
    username = $Username
    played = $true
    owned = $true
}

if (-not $IncludeExpansions) {
    $toolArgs.subtype = 'boardgame'
}

$result = Invoke-BggMcpTool -ToolName 'bgg-collection' -Arguments $toolArgs -Endpoint $Endpoint -Username $Username -ApiKey $ApiKey -Cookie $Cookie

$items = @($result)

if (-not $items -or $items.Count -eq 0) {
    Write-Warning 'No played games found.'
    return
}

$played = $items |
    Sort-Object @{ Expression = { [int](Get-CollectionValue -Item $_ -PropertyName 'numplays') }; Descending = $true }, @{ Expression = { $_.name } } |
    Select-Object @{ Name = 'bgg_id'; Expression = { $_.objectid } },
                  @{ Name = 'name'; Expression = { $_.name } },
                  @{ Name = 'year_published'; Expression = { $_.yearpublished } },
                  @{ Name = 'rating'; Expression = { [double](Get-CollectionValue -Item $_ -PropertyName 'rating') } },
                  @{ Name = 'num_plays'; Expression = { [int](Get-CollectionValue -Item $_ -PropertyName 'numplays') } }

$jsonPath = Join-Path $OutDir 'played-games.json'
$csvPath = Join-Path $OutDir 'played-games.csv'

$played | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
$played | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    TotalPlayed = $played.Count
    Json = $jsonPath
    Csv = $csvPath
}
