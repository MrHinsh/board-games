[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [int]$Top = 10,
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [string]$OutDir = '.\\data\\reports\\top',
    [switch]$IncludeExpansions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\\..\\..\\mrhinsh-bg-shared\\scripts\\Invoke-BggMcp.ps1"

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
        Where-Object { [double](Get-CollectionValue -Item $_ -PropertyName 'rating') -gt 0 } |
        Sort-Object @{ Expression = { [double](Get-CollectionValue -Item $_ -PropertyName 'rating') }; Descending = $true },
                                @{ Expression = { [int](Get-CollectionValue -Item $_ -PropertyName 'numplays') }; Descending = $true },
                @{ Expression = { $_.name } } |
    Select-Object -First $Top |
    Select-Object @{ Name = 'rank'; Expression = { $script:i = ($script:i + 1); $script:i } },
                  @{ Name = 'bgg_id'; Expression = { $_.objectid } },
                  @{ Name = 'name'; Expression = { $_.name } },
                  @{ Name = 'year_published'; Expression = { $_.yearpublished } },
                                    @{ Name = 'rating'; Expression = { [double](Get-CollectionValue -Item $_ -PropertyName 'rating') } },
                                    @{ Name = 'num_plays'; Expression = { [int](Get-CollectionValue -Item $_ -PropertyName 'numplays') } }

$jsonPath = Join-Path $OutDir 'top-10.json'
$csvPath = Join-Path $OutDir 'top-10.csv'

$ranked | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
$ranked | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$ranked

[pscustomobject]@{
    TopCount = @($ranked).Count
    Json = $jsonPath
    Csv = $csvPath
}
