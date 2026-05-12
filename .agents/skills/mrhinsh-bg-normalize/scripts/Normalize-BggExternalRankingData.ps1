[CmdletBinding()]
param(
    [string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
    [string]$TierExportDir = '.\data\publish\tiers',
    [string]$RankingExportDir = '.\data\publish\ranking',
    [string]$TierImportPath = '.\data\publish\tiers\tier-engine-import.csv',
    [string]$RankingImportDir = '.\data\publish\ranking\import',
    [string]$PubMeepleInputDir = '.\data\raw\pubmeeple\in',
    [string]$PubMeepleOutputDir = '.\data\raw\pubmeeple\out',
    [string]$PendingTierMovesPath = '.\data\publish\queue\pending-tier-moves.json',
    [string]$NormalizedRankingImportPath = '.\data\working\ranking\external-ordering.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\..\mrhinsh-bg-shared\scripts\BggTierHelpers.ps1"

function Get-NormalizedTitleKey {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    $collapsed = [regex]::Replace($Value.Trim(), '\s+', ' ')
    return $collapsed.ToUpperInvariant()
}

function Test-ColumnExists {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row,

        [Parameter(Mandatory = $true)]
        [string]$ColumnName
    )

    return $null -ne $Row.PSObject.Properties[$ColumnName]
}

function Get-ReorderedRowsFromPubMeeple {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$RankingRows,

        [Parameter(Mandatory = $true)]
        [string]$PubMeepleCsvPath,

        [string]$ImportRankColumn = 'rank',
        [string]$ImportTitleColumn = 'item',
        [string]$RankingTitleColumn = 'name'
    )

    $result = [ordered]@{
        Rows = @($RankingRows)
        MatchedCount = 0
    }

    if (-not (Test-Path $PubMeepleCsvPath)) {
        return [pscustomobject]$result
    }

    $localRankingRows = @($RankingRows)
    if ($localRankingRows.Count -eq 0) {
        return [pscustomobject]$result
    }

    if (-not (Test-ColumnExists -Row $localRankingRows[0] -ColumnName $RankingTitleColumn)) {
        throw "Ranking rows are missing required column '$RankingTitleColumn' for PubMeeple import: $PubMeepleCsvPath"
    }

    $rankingByKey = @{}
    foreach ($row in $localRankingRows) {
        $title = [string]$row.$RankingTitleColumn
        $key = Get-NormalizedTitleKey -Value $title
        if ($key -eq '') {
            throw "Ranking rows contain a blank title in column '$RankingTitleColumn' while processing $PubMeepleCsvPath"
        }

        if ($rankingByKey.ContainsKey($key)) {
            throw "Ranking rows contain duplicate title '$title' in column '$RankingTitleColumn' while processing $PubMeepleCsvPath"
        }

        $rankingByKey[$key] = $row
    }

    $importRows = @(Import-Csv -Path $PubMeepleCsvPath)
    if ($importRows.Count -eq 0) {
        return [pscustomobject]$result
    }

    if (-not (Test-ColumnExists -Row $importRows[0] -ColumnName $ImportTitleColumn)) {
        throw "PubMeeple CSV is missing required column '$ImportTitleColumn': $PubMeepleCsvPath"
    }

    if (-not (Test-ColumnExists -Row $importRows[0] -ColumnName $ImportRankColumn)) {
        throw "PubMeeple CSV is missing required column '$ImportRankColumn': $PubMeepleCsvPath"
    }

    $orderedImports = [System.Collections.Generic.List[object]]::new()
    $seenImportKeys = @{}
    $sequence = 0

    foreach ($row in $importRows) {
        $sequence++
        $title = [string]$row.$ImportTitleColumn
        $key = Get-NormalizedTitleKey -Value $title
        if ($key -eq '') {
            continue
        }

        if ($seenImportKeys.ContainsKey($key)) {
            throw "PubMeeple CSV contains duplicate title '$title': $PubMeepleCsvPath"
        }

        if (-not $rankingByKey.ContainsKey($key)) {
            throw "PubMeeple CSV title '$title' does not match any ranking row in $PubMeepleCsvPath"
        }

        $rankValue = $sequence
        $parsedRank = 0.0
        if (-not [string]::IsNullOrWhiteSpace([string]$row.$ImportRankColumn) -and [double]::TryParse([string]$row.$ImportRankColumn, [ref]$parsedRank)) {
            $rankValue = $parsedRank
        }

        [void]$orderedImports.Add([pscustomobject]@{
            key = $key
            rank = $rankValue
            sequence = $sequence
        })
        $seenImportKeys[$key] = $true
    }

    if ($orderedImports.Count -eq 0) {
        return [pscustomobject]$result
    }

    $reorderedRows = [System.Collections.Generic.List[object]]::new()
    $consumed = @{}

    foreach ($item in @($orderedImports | Sort-Object @{ Expression = { [double]$_.rank } }, @{ Expression = { [int]$_.sequence } })) {
        [void]$reorderedRows.Add($rankingByKey[$item.key])
        $consumed[$item.key] = $true
    }

    foreach ($row in $localRankingRows) {
        $key = Get-NormalizedTitleKey -Value ([string]$row.$RankingTitleColumn)
        if (-not $consumed.ContainsKey($key)) {
            [void]$reorderedRows.Add($row)
        }
    }

    $result.Rows = @($reorderedRows)
    $result.MatchedCount = $orderedImports.Count
    return [pscustomobject]$result
}

$membership = @(Read-JsonFile -Path $MembershipPath -Default @())
if ($membership.Count -eq 0) {
    throw "Tier membership file is empty or missing: $MembershipPath"
}

New-Item -ItemType Directory -Path $TierExportDir -Force | Out-Null
New-Item -ItemType Directory -Path $RankingExportDir -Force | Out-Null
New-Item -ItemType Directory -Path $PubMeepleInputDir -Force | Out-Null
New-Item -ItemType Directory -Path $PubMeepleOutputDir -Force | Out-Null

Get-ChildItem -Path $RankingExportDir -Filter 'tier-*-ranking.csv' -File -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Path $PubMeepleInputDir -Filter 'tier-*-ranking.txt' -File -ErrorAction SilentlyContinue | Remove-Item -Force

$engineExport = $membership | Select-Object tier, source_bucket, rank_in_tier, bgg_id, name, current_rating, num_plays, collection, previously_owned, want_to_play, want_to_buy, collection_to_exit, collection_status, players, complexity, bgg_rating, bgg_game_url
$engineExport | Export-Csv -Path (Join-Path $TierExportDir 'tier-engine-export.csv') -NoTypeInformation -Encoding UTF8
Write-JsonFile -Path (Join-Path $TierExportDir 'tier-engine-export.json') -Value $engineExport

$normalizedRanking = [System.Collections.Generic.List[object]]::new()

foreach ($group in ($membership | Where-Object { $_.tier -ne 'U' } | Group-Object ranking_group)) {
    $first = $group.Group | Select-Object -First 1
    $fileName = if ([string]$first.tier -eq 'F') {
        'tier-F-ranking.csv'
    } else {
        "tier-$($first.tier)-ranking.csv"
    }

    $rows = @($group.Group | Sort-Object @{ Expression = { if ($null -eq $_.rank_in_tier -or $_.rank_in_tier -eq '') { [int]::MaxValue } else { [int]$_.rank_in_tier } } }, @{ Expression = { [int]$_.num_plays }; Descending = $true }, name | Select-Object tier, source_bucket, rank_in_tier, bgg_id, name, current_rating, num_plays, collection, previously_owned, want_to_play, want_to_buy, collection_to_exit, collection_status, bgg_game_url)

    $pubMeepleFilePath = Join-Path $PubMeepleOutputDir $fileName
    $pubMeepleImport = Get-ReorderedRowsFromPubMeeple -RankingRows $rows -PubMeepleCsvPath $pubMeepleFilePath
    $rows = @($pubMeepleImport.Rows)

    $rankingFilePath = Join-Path $RankingExportDir $fileName
    $rows | Export-Csv -Path $rankingFilePath -NoTypeInformation -Encoding UTF8
    @($rows | ForEach-Object { [string]$_.name }) | Set-Content -Path (Join-Path $PubMeepleInputDir ([System.IO.Path]::GetFileNameWithoutExtension($fileName) + '.txt')) -Encoding UTF8

    if ($pubMeepleImport.MatchedCount -gt 0) {
        $sequence = 0
        foreach ($row in $rows) {
            $sequence++
            [void]$normalizedRanking.Add([pscustomobject]@{
                tier = [string]$row.tier
                source_bucket = [int]$row.source_bucket
                bgg_id = [int]$row.bgg_id
                rank_in_tier = $sequence
                import_file = $fileName
            })
        }
    }
}

$pendingTierMoves = @()
if (Test-Path $TierImportPath) {
    $pendingTierMoves = @(Import-TabularData -Path $TierImportPath | ForEach-Object {
        [pscustomobject]@{
            bgg_id = [int]$_.bgg_id
            tier = [string]$_.tier
            source_bucket = if ($_.PSObject.Properties['source_bucket'] -and $_.source_bucket -ne '') { [int]$_.source_bucket } else { -1 }
            notes = if ($_.PSObject.Properties['notes']) { [string]$_.notes } else { '' }
        }
    })
}
Write-JsonFile -Path $PendingTierMovesPath -Value $pendingTierMoves

if (Test-Path $RankingImportDir) {
    $files = Get-ChildItem -Path $RankingImportDir -File | Where-Object { $_.Extension -in '.csv', '.json' } | Sort-Object Name
    foreach ($file in $files) {
        $sequence = 0
        foreach ($item in @(Import-TabularData -Path $file.FullName)) {
            $sequence++
            [void]$normalizedRanking.Add([pscustomobject]@{
                tier = if ($item.PSObject.Properties['tier']) { [string]$item.tier } else { '' }
                source_bucket = if ($item.PSObject.Properties['source_bucket'] -and $item.source_bucket -ne '') { [int]$item.source_bucket } else { -1 }
                bgg_id = [int]$item.bgg_id
                rank_in_tier = if ($item.PSObject.Properties['rank_in_tier'] -and $item.rank_in_tier -ne '') { [int]$item.rank_in_tier } else { $sequence }
                import_file = $file.Name
            })
        }
    }
}
Write-JsonFile -Path $NormalizedRankingImportPath -Value @($normalizedRanking)

[pscustomobject]@{
    TierExportDir = $TierExportDir
    RankingExportDir = $RankingExportDir
    PendingTierMovesPath = $PendingTierMovesPath
    NormalizedRankingImportPath = $NormalizedRankingImportPath
    TierMoveCount = @($pendingTierMoves).Count
    RankingImportCount = $normalizedRanking.Count
}
