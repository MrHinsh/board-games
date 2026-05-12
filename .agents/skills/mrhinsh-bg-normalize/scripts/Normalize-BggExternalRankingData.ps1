[CmdletBinding()]
param(
    [string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
    [string]$TierExportDir = '.\data\publish\tiers',
    [string]$RankingExportDir = '.\data\publish\ranking',
    [string]$PubMeepleInputDir = '.\data\raw\pubmeeple\in',
    [string]$PubMeepleOutputDir = '.\data\raw\pubmeeple\out',
    [string]$TierImportPath = '.\data\publish\tiers\tier-engine-import.csv',
    [string]$RankingImportDir = '.\data\publish\ranking\import',
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
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string]$PubMeepleCsvPath,

        [string]$ImportRankColumn = 'rank',
        [string]$ImportTitleColumn = 'item',
        [string]$RankingTitleColumn = 'name'
    )

    if ($Rows.Count -eq 0) {
        return @()
    }

    $importRows = @(Import-Csv -Path $PubMeepleCsvPath)
    if ($importRows.Count -eq 0) {
        throw "PubMeeple CSV is empty: $PubMeepleCsvPath"
    }

    if (-not (Test-ColumnExists -Row $importRows[0] -ColumnName $ImportTitleColumn)) {
        throw "PubMeeple CSV is missing required column '$ImportTitleColumn': $PubMeepleCsvPath"
    }

    if (-not (Test-ColumnExists -Row $importRows[0] -ColumnName $ImportRankColumn)) {
        throw "PubMeeple CSV is missing required column '$ImportRankColumn': $PubMeepleCsvPath"
    }

    $rankingByKey = @{}
    foreach ($row in $Rows) {
        $title = [string]$row.$RankingTitleColumn
        $key = Get-NormalizedTitleKey -Value $title
        if ($key -eq '') {
            throw "Generated ranking rows contain a blank title in column '$RankingTitleColumn'."
        }

        if ($rankingByKey.ContainsKey($key)) {
            throw "Generated ranking rows contain duplicate title matches for '$title' in column '$RankingTitleColumn'."
        }

        $rankingByKey[$key] = $row
    }

    $orderedImports = [System.Collections.Generic.List[object]]::new()
    $seenImportKeys = @{}
    $inputSequence = 0
    foreach ($row in $importRows) {
        $inputSequence++

        $title = [string]$row.$ImportTitleColumn
        $key = Get-NormalizedTitleKey -Value $title
        if ($key -eq '') {
            continue
        }

        if ($seenImportKeys.ContainsKey($key)) {
            throw "PubMeeple CSV contains duplicate title matches for '$title' in column '$ImportTitleColumn': $PubMeepleCsvPath"
        }

        if (-not $rankingByKey.ContainsKey($key)) {
            throw "PubMeeple CSV title '$title' does not match any generated ranking row for '$PubMeepleCsvPath'."
        }

        $rankValue = $inputSequence
        $parsedRank = 0.0
        if (-not [string]::IsNullOrWhiteSpace([string]$row.$ImportRankColumn) -and [double]::TryParse([string]$row.$ImportRankColumn, [ref]$parsedRank)) {
            $rankValue = $parsedRank
        }

        [void]$orderedImports.Add([pscustomobject]@{
            key = $key
            rank = $rankValue
            sequence = $inputSequence
        })
        $seenImportKeys[$key] = $true
    }

    if ($orderedImports.Count -eq 0) {
        throw "PubMeeple CSV did not contain any usable rows from columns '$ImportRankColumn' and '$ImportTitleColumn': $PubMeepleCsvPath"
    }

    $reorderedRows = [System.Collections.Generic.List[object]]::new()
    $consumed = @{}
    foreach ($item in @($orderedImports | Sort-Object @{ Expression = { [double]$_.rank } }, @{ Expression = { [int]$_.sequence } })) {
        [void]$reorderedRows.Add($rankingByKey[$item.key])
        $consumed[$item.key] = $true
    }

    foreach ($row in $Rows) {
        $key = Get-NormalizedTitleKey -Value ([string]$row.$RankingTitleColumn)
        if (-not $consumed.ContainsKey($key)) {
            [void]$reorderedRows.Add($row)
        }
    }

    return @($reorderedRows)
}

$membership = @(Read-JsonFile -Path $MembershipPath -Default @())
if ($membership.Count -eq 0) {
    throw "Tier membership file is empty or missing: $MembershipPath"
}

New-Item -ItemType Directory -Path $TierExportDir -Force | Out-Null
New-Item -ItemType Directory -Path $RankingExportDir -Force | Out-Null
New-Item -ItemType Directory -Path $PubMeepleInputDir -Force | Out-Null

Get-ChildItem -Path $RankingExportDir -Filter 'tier-*-ranking.csv' -File -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Path $RankingExportDir -Filter 'tier-*-ranking.txt' -File -ErrorAction SilentlyContinue | Remove-Item -Force
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
    $csvPath = Join-Path $RankingExportDir $fileName
    $txtPath = Join-Path $PubMeepleInputDir ([System.IO.Path]::ChangeExtension($fileName, '.txt'))
    $pubMeeplePath = Join-Path $PubMeepleOutputDir $fileName

    if (Test-Path $pubMeeplePath) {
        $rows = @(Get-ReorderedRowsFromPubMeeple -Rows $rows -PubMeepleCsvPath $pubMeeplePath)
        $sequence = 0
        foreach ($row in $rows) {
            $sequence++
            [void]$normalizedRanking.Add([pscustomobject]@{
                tier = [string]$row.tier
                source_bucket = [int]$row.source_bucket
                bgg_id = [int]$row.bgg_id
                rank_in_tier = $sequence
                import_file = [System.IO.Path]::GetFileName($pubMeeplePath)
            })
        }
    }

    $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    @($rows | ForEach-Object { [string]$_.name }) | Set-Content -Path $txtPath -Encoding UTF8
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
    PubMeepleInputDir = $PubMeepleInputDir
    PubMeepleOutputDir = $PubMeepleOutputDir
    PendingTierMovesPath = $PendingTierMovesPath
    NormalizedRankingImportPath = $NormalizedRankingImportPath
    TierMoveCount = @($pendingTierMoves).Count
    RankingImportCount = $normalizedRanking.Count
}
