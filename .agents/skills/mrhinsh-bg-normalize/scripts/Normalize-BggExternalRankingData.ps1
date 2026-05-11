[CmdletBinding()]
param(
    [string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
    [string]$TierExportDir = '.\data\publish\tiers',
    [string]$RankingExportDir = '.\data\publish\ranking',
    [string]$TierImportPath = '.\data\publish\tiers\tier-engine-import.csv',
    [string]$RankingImportDir = '.\data\publish\ranking\import',
    [string]$PendingTierMovesPath = '.\data\publish\queue\pending-tier-moves.json',
    [string]$NormalizedRankingImportPath = '.\data\working\ranking\external-ordering.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\..\mrhinsh-bg-shared\scripts\BggTierHelpers.ps1"

$membership = @(Read-JsonFile -Path $MembershipPath -Default @())
if ($membership.Count -eq 0) {
    throw "Tier membership file is empty or missing: $MembershipPath"
}

New-Item -ItemType Directory -Path $TierExportDir -Force | Out-Null
New-Item -ItemType Directory -Path $RankingExportDir -Force | Out-Null

Get-ChildItem -Path $RankingExportDir -Filter 'tier-*-ranking.csv' -File -ErrorAction SilentlyContinue | Remove-Item -Force

$engineExport = $membership | Select-Object tier, source_bucket, rank_in_tier, bgg_id, name, current_rating, num_plays, players, complexity, bgg_rating, bgg_game_url
$engineExport | Export-Csv -Path (Join-Path $TierExportDir 'tier-engine-export.csv') -NoTypeInformation -Encoding UTF8
Write-JsonFile -Path (Join-Path $TierExportDir 'tier-engine-export.json') -Value $engineExport

foreach ($group in ($membership | Where-Object { $_.tier -ne 'U' } | Group-Object ranking_group)) {
    $first = $group.Group | Select-Object -First 1
    $fileName = if ([string]$first.tier -eq 'F') {
        'tier-F-ranking.csv'
    } else {
        "tier-$($first.tier)-ranking.csv"
    }

    $rows = @($group.Group | Sort-Object @{ Expression = { if ($null -eq $_.rank_in_tier -or $_.rank_in_tier -eq '') { [int]::MaxValue } else { [int]$_.rank_in_tier } } }, @{ Expression = { [int]$_.num_plays }; Descending = $true }, name | Select-Object tier, source_bucket, rank_in_tier, bgg_id, name, current_rating, num_plays, bgg_game_url)
    $rows | Export-Csv -Path (Join-Path $RankingExportDir $fileName) -NoTypeInformation -Encoding UTF8
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

$normalizedRanking = [System.Collections.Generic.List[object]]::new()
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
