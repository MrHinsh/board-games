[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [string]$OutDir = '.\\data\\working\\canonical',
    [string]$OutCsvPath = '.\\data\\reports\\ranking\\played-games.csv',
    [switch]$IncludeExpansions,
    [ValidateSet('none', 'players', 'complexity', 'year')]
    [string]$GroupBy = 'players',
    [switch]$EnrichWithDetails = $true
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

function Get-DetailValue {
    param(
        [object]$Item,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [object]$DefaultValue = $null
    )

    if ($null -eq $Item) {
        return $DefaultValue
    }

    $property = $Item.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value -or $property.Value -eq '') {
        return $DefaultValue
    }

    return $property.Value
}

function Get-GroupKey {
    param(
        [object]$Item,

        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    switch ($Mode) {
        'players' {
            $players = Get-DetailValue -Item $Item -PropertyName 'players' -DefaultValue 'unknown'
            if ([string]::IsNullOrWhiteSpace([string]$players)) {
                return 'unknown'
            }

            return [string]$players
        }
        'complexity' {
            $complexity = [double](Get-DetailValue -Item $Item -PropertyName 'complexity' -DefaultValue 0)
            if ($complexity -le 0) {
                return 'unknown'
            }

            $bucket = [math]::Round($complexity * 2) / 2
            return "complexity-$bucket"
        }
        'year' {
            $year = [int](Get-DetailValue -Item $Item -PropertyName 'year_published' -DefaultValue 0)
            if ($year -le 0) {
                return 'unknown'
            }

            $decade = [math]::Floor($year / 10) * 10
            return "${decade}s"
        }
        default {
            return 'all'
        }
    }
}

function Invoke-BggDetailsBatch {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ids,

        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [string]$ApiKey,

        [string]$Cookie,

        [Parameter(Mandatory = $true)]
        [string]$Username
    )

    if (-not $Ids -or $Ids.Count -eq 0) {
        return @()
    }

    return @(Invoke-BggMcpTool -ToolName 'bgg-details' -Arguments @{ ids = $Ids } -Endpoint $Endpoint -Username $Username -ApiKey $ApiKey -Cookie $Cookie)
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$csvDir = Split-Path -Path $OutCsvPath -Parent
if ($csvDir -and -not (Test-Path $csvDir)) {
    New-Item -ItemType Directory -Path $csvDir | Out-Null
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
    Sort-Object @{ Expression = { [int](Get-CollectionValue -Item $_ -PropertyName 'numplays') }; Descending = $true }, @{ Expression = { Get-CollectionValue -Item $_ -PropertyName 'name' -DefaultValue '' } } |
    Select-Object @{ Name = 'bgg_id'; Expression = { Get-CollectionValue -Item $_ -PropertyName 'objectid' } },
                  @{ Name = 'name'; Expression = { Get-CollectionValue -Item $_ -PropertyName 'name' -DefaultValue '' } },
                  @{ Name = 'year_published'; Expression = { Get-CollectionValue -Item $_ -PropertyName 'yearpublished' } },
                  @{ Name = 'rating'; Expression = { [double](Get-CollectionValue -Item $_ -PropertyName 'rating') } },
                  @{ Name = 'num_plays'; Expression = { [int](Get-CollectionValue -Item $_ -PropertyName 'numplays') } }

if ($EnrichWithDetails) {
    $detailMap = @{}
    $ids = @($played | ForEach-Object { [int]$_.bgg_id } | Select-Object -Unique)

    foreach ($batch in ($ids | ForEach-Object -Begin { $buffer = New-Object System.Collections.Generic.List[int] } -Process {
        [void]$buffer.Add($_)
        if ($buffer.Count -ge 20) {
            ,@($buffer)
            $buffer.Clear()
        }
    } -End {
        if ($buffer.Count -gt 0) {
            ,@($buffer)
        }
    })) {
        $batchDetails = Invoke-BggDetailsBatch -Ids $batch -Endpoint $Endpoint -ApiKey $ApiKey -Cookie $Cookie -Username $Username
        foreach ($detail in $batchDetails) {
            if ($null -ne $detail -and $null -ne $detail.id) {
                $detailMap[[int]$detail.id] = $detail
            }
        }
    }

    $played = $played | ForEach-Object {
        $detail = $detailMap[[int]$_.bgg_id]

        [pscustomobject]@{
            group_key      = Get-GroupKey -Item $detail -Mode $GroupBy
            bgg_id         = $_.bgg_id
            name           = $_.name
            year_published = $_.year_published
            rating         = $_.rating
            num_plays      = $_.num_plays
            players        = Get-DetailValue -Item $detail -PropertyName 'players' -DefaultValue $null
            complexity     = Get-DetailValue -Item $detail -PropertyName 'complexity' -DefaultValue $null
            bgg_rating     = Get-DetailValue -Item $detail -PropertyName 'bgg_rating' -DefaultValue $null
            num_ratings    = Get-DetailValue -Item $detail -PropertyName 'num_ratings' -DefaultValue $null
            categories     = Get-DetailValue -Item $detail -PropertyName 'categories' -DefaultValue @()
            mechanics      = Get-DetailValue -Item $detail -PropertyName 'mechanics' -DefaultValue @()
        }
    }
}

$played = $played |
    Sort-Object group_key, @{ Expression = { [int]$_.num_plays }; Descending = $true }, @{ Expression = { $_.name } }

$jsonPath = Join-Path $OutDir 'games.json'
$csvPath = $OutCsvPath

$played | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
$played | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    TotalPlayed = $played.Count
    GroupBy = $GroupBy
    Json = $jsonPath
    Csv = $csvPath
}
