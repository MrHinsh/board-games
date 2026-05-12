[CmdletBinding()]
param(
    [string]$InputPath = '.\data\working\canonical\games.json',
    [string]$OutDir = '.\data\reports\ranking',
    [string]$UnratedPath = '.\data\working\unrated\intake.json',
    [string]$UnratedRankedPath = '.\data\working\unrated\intake-ranked.json',
    [string]$GroupField = 'group_key'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $InputPath)) {
    throw "Input file not found: $InputPath"
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$items = @(Get-Content -Path $InputPath -Raw | ConvertFrom-Json)

if ($items.Count -eq 0) {
    Write-Warning 'No played games found to stackrank.'
    return
}

function Get-FieldValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Item,

        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [object]$DefaultValue = $null
    )

    $property = $Item.PSObject.Properties[$FieldName]
    if ($null -eq $property -or $null -eq $property.Value -or $property.Value -eq '') {
        return $DefaultValue
    }

    return $property.Value
}

function Get-ProposedRating {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Rank,

        [Parameter(Mandatory = $true)]
        [int]$GroupCount,

        [Parameter(Mandatory = $true)]
        [int]$TargetBase
    )

    if ($GroupCount -le 1) {
        return [math]::Round(($TargetBase + 0.999), 3)
    }

    $fraction = (($GroupCount - $Rank) / ($GroupCount - 1)) * 0.999
    return [math]::Round(($TargetBase + $fraction), 3)
}

$deduped = $items |
    Group-Object { Get-FieldValue -Item $_ -FieldName 'bgg_id' -DefaultValue 0 } |
    ForEach-Object {
        $_.Group |
            Sort-Object @{ Expression = { [double](Get-FieldValue -Item $_ -FieldName 'rating' -DefaultValue 0) }; Descending = $true },
                        @{ Expression = { [int](Get-FieldValue -Item $_ -FieldName 'num_plays' -DefaultValue 0) }; Descending = $true },
                        @{ Expression = { [double](Get-FieldValue -Item $_ -FieldName 'bgg_rating' -DefaultValue 0) }; Descending = $true },
                        @{ Expression = { Get-FieldValue -Item $_ -FieldName 'name' -DefaultValue '' } } |
            Select-Object -First 1
    }

$rated = @($deduped | Where-Object { [double](Get-FieldValue -Item $_ -FieldName 'rating' -DefaultValue 0) -gt 0 })
$unrated = @($deduped | Where-Object { [double](Get-FieldValue -Item $_ -FieldName 'rating' -DefaultValue 0) -le 0 })

$ranked = foreach ($ratingBucket in ($rated | Group-Object { [int][math]::Floor([double](Get-FieldValue -Item $_ -FieldName 'rating' -DefaultValue 0)) })) {
    $bucketValue = [int]$ratingBucket.Name
    $targetBase = $bucketValue - 1
    if ($targetBase -lt 1) {
        $targetBase = 1
    }

    $ordered = $ratingBucket.Group |
        Sort-Object @{ Expression = { [double](Get-FieldValue -Item $_ -FieldName 'rating' -DefaultValue 0) }; Descending = $true },
                    @{ Expression = { [int](Get-FieldValue -Item $_ -FieldName 'num_plays' -DefaultValue 0) }; Descending = $true },
                    @{ Expression = { [double](Get-FieldValue -Item $_ -FieldName 'bgg_rating' -DefaultValue 0) }; Descending = $true },
                    @{ Expression = { Get-FieldValue -Item $_ -FieldName 'name' -DefaultValue '' } }

    $index = 0
    foreach ($item in $ordered) {
        $index++
        $groupCount = @($ratingBucket.Group).Count

        [pscustomobject]@{
            group_key = Get-FieldValue -Item $item -FieldName $GroupField -DefaultValue 'all'
            stack_rank = $index
            group_count = $groupCount
            source_rating_bucket = $bucketValue
            target_rating_band = "$targetBase.000-$targetBase.999"
            bgg_id = Get-FieldValue -Item $item -FieldName 'bgg_id' -DefaultValue 0
            name = Get-FieldValue -Item $item -FieldName 'name' -DefaultValue ''
            current_rating = [double](Get-FieldValue -Item $item -FieldName 'rating' -DefaultValue 0)
            proposed_rating = Get-ProposedRating -Rank $index -GroupCount $groupCount -TargetBase $targetBase
            num_plays = [int](Get-FieldValue -Item $item -FieldName 'num_plays' -DefaultValue 0)
            players = Get-FieldValue -Item $item -FieldName 'players' -DefaultValue $null
            complexity = Get-FieldValue -Item $item -FieldName 'complexity' -DefaultValue $null
            bgg_rating = Get-FieldValue -Item $item -FieldName 'bgg_rating' -DefaultValue $null
            bgg_comment = Get-FieldValue -Item $item -FieldName 'bgg_comment' -DefaultValue ''
            notes = Get-FieldValue -Item $item -FieldName 'notes' -DefaultValue ''
            categories = Get-FieldValue -Item $item -FieldName 'categories' -DefaultValue @()
            mechanics = Get-FieldValue -Item $item -FieldName 'mechanics' -DefaultValue @()
        }
    }
}

$jsonPath = Join-Path $OutDir 'stackranked.json'
$csvPath = Join-Path $OutDir 'stackranked.csv'
$unratedJsonPath = $UnratedPath
$unratedCsvPath = Join-Path $OutDir 'unrated.csv'
$unratedPlayedCsvPath = Join-Path $OutDir 'unrated-played.csv'

$unratedDir = Split-Path -Path $UnratedPath -Parent
if ($unratedDir -and -not (Test-Path $unratedDir)) {
    New-Item -ItemType Directory -Path $unratedDir | Out-Null
}

$unratedRankedDir = Split-Path -Path $UnratedRankedPath -Parent
if ($unratedRankedDir -and -not (Test-Path $unratedRankedDir)) {
    New-Item -ItemType Directory -Path $unratedRankedDir | Out-Null
}

$ranked | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
$ranked | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$unratedExport = @()

$unrated | Select-Object @{ Name = 'group_key'; Expression = { Get-FieldValue -Item $_ -FieldName $GroupField -DefaultValue 'all' } },
                          @{ Name = 'bgg_id'; Expression = { Get-FieldValue -Item $_ -FieldName 'bgg_id' -DefaultValue 0 } },
                          @{ Name = 'name'; Expression = { Get-FieldValue -Item $_ -FieldName 'name' -DefaultValue '' } },
                          @{ Name = 'current_rating'; Expression = { [double](Get-FieldValue -Item $_ -FieldName 'rating' -DefaultValue 0) } },
                          @{ Name = 'num_plays'; Expression = { [int](Get-FieldValue -Item $_ -FieldName 'num_plays' -DefaultValue 0) } },
                          @{ Name = 'players'; Expression = { Get-FieldValue -Item $_ -FieldName 'players' -DefaultValue $null } },
                          @{ Name = 'complexity'; Expression = { Get-FieldValue -Item $_ -FieldName 'complexity' -DefaultValue $null } },
                          @{ Name = 'bgg_rating'; Expression = { Get-FieldValue -Item $_ -FieldName 'bgg_rating' -DefaultValue $null } },
                          @{ Name = 'bgg_comment'; Expression = { Get-FieldValue -Item $_ -FieldName 'bgg_comment' -DefaultValue '' } },
                          @{ Name = 'notes'; Expression = { Get-FieldValue -Item $_ -FieldName 'notes' -DefaultValue '' } },
                          @{ Name = 'categories'; Expression = { Get-FieldValue -Item $_ -FieldName 'categories' -DefaultValue @() } },
                          @{ Name = 'mechanics'; Expression = { Get-FieldValue -Item $_ -FieldName 'mechanics' -DefaultValue @() } } |
    Tee-Object -Variable unratedExport |
    ConvertTo-Json -Depth 10 | Set-Content -Path $unratedJsonPath -Encoding UTF8

$unratedExport | Export-Csv -Path $unratedCsvPath -NoTypeInformation -Encoding UTF8
$unratedExport |
    Where-Object { [int](Get-FieldValue -Item $_ -FieldName 'num_plays' -DefaultValue 0) -gt 0 } |
    Export-Csv -Path $unratedPlayedCsvPath -NoTypeInformation -Encoding UTF8

$unratedExport |
    Sort-Object @{ Expression = { [int](Get-FieldValue -Item $_ -FieldName 'num_plays' -DefaultValue 0) }; Descending = $true },
                @{ Expression = { Get-FieldValue -Item $_ -FieldName 'name' -DefaultValue '' } } |
    ConvertTo-Json -Depth 10 | Set-Content -Path $UnratedRankedPath -Encoding UTF8

$ranked

[pscustomobject]@{
    TotalRanked = @($ranked).Count
    TotalUnrated = @($unrated).Count
    Json = $jsonPath
    Csv = $csvPath
    UnratedJson = $unratedJsonPath
    UnratedCsv = $unratedCsvPath
    UnratedPlayedCsv = $unratedPlayedCsvPath
    UnratedRankedJson = $UnratedRankedPath
}