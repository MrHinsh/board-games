[CmdletBinding()]
param(
    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
    [string]$TiersPath = '.\data\working\ranking\tiers.json',
    [string]$TierExportJson = '.\data\publish\tiers\tier-engine-export.json',
    [string]$TierExportCsv = '.\data\publish\tiers\tier-engine-export.csv',
    [switch]$IncludeUnrated,
    [switch]$ForceRebuildRanks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\..\mrhinsh-bg-shared\scripts\BggTierHelpers.ps1"

$canonical = @(Read-JsonFile -Path $CanonicalPath -Default @())
if ($canonical.Count -eq 0) {
    throw "Canonical file is empty or missing: $CanonicalPath"
}

$existingMembership = @(Read-JsonFile -Path $MembershipPath -Default @())
$existingById = @{}
foreach ($item in $existingMembership) {
    $existingById[[int]$item.bgg_id] = $item
}

$membership = foreach ($game in ($canonical | Sort-Object @{ Expression = { [double]$_.rating }; Descending = $true }, @{ Expression = { [int]$_.num_plays }; Descending = $true }, name)) {
    $gameId = [int]$game.bgg_id
    $currentRating = [double]$game.rating
    $existing = $existingById[$gameId]
    $existingTier = if ($null -ne $existing -and $existing.PSObject.Properties['tier']) { [string]$existing.tier } else { '' }
    $existingBucket = if ($null -ne $existing -and $existing.PSObject.Properties['source_bucket']) { [int]$existing.source_bucket } else { -1 }
    if ($existingTier -eq 'X') {
        $tier = 'X'
        $sourceBucket = if ($existingBucket -ge 0) { $existingBucket } else { 0 }
    } else {
        $sourceBucket = Get-InitialBucketFromRating -Rating $currentRating -ExistingBucket $existingBucket
        $tier = Get-TierLabelFromBucket -Bucket $sourceBucket
    }

    if (-not $IncludeUnrated -and $tier -eq 'U') {
        continue
    }

    $rankInTier = $null
    $rankingGroup = Get-TierRankingGroupKey -Tier $tier -SourceBucket $sourceBucket
    if (-not (Test-IsNonRankedTier -Tier $tier) -and -not $ForceRebuildRanks -and $null -ne $existing -and $existing.PSObject.Properties['rank_in_tier']) {
        $existingGroup = if ($existing.PSObject.Properties['ranking_group']) { [string]$existing.ranking_group } else { '' }
        if ($existingGroup -eq $rankingGroup) {
            $rankInTier = $existing.rank_in_tier
        }
    }

    if ($tier -eq 'F' -and -not $ForceRebuildRanks -and $null -ne $existing -and -not $existing.PSObject.Properties['ranking_group']) {
        $rankInTier = $existing.rank_in_tier
    }

    $collection = if ($game.PSObject.Properties['collection']) { [bool]$game.collection } else { $null }
    $previouslyOwned = if ($game.PSObject.Properties['previously_owned']) { [bool]$game.previously_owned } else { $null }
    $wantToPlay = if ($game.PSObject.Properties['want_to_play']) { [bool]$game.want_to_play } else { $null }
    $wantToBuy = if ($game.PSObject.Properties['want_to_buy']) { [bool]$game.want_to_buy } else { $null }
    $collectionToExit = if ($game.PSObject.Properties['collection_to_exit']) { [bool]$game.collection_to_exit } else { $null }
    $collectionStatus = if ($game.PSObject.Properties['collection_status']) { [string]$game.collection_status } else { '' }

    [pscustomobject]@{
        tier = $tier
        tier_sort = Get-TierSortWeight -Tier $tier
        ranking_group = $rankingGroup
        source_bucket = $sourceBucket
        rank_in_tier = $rankInTier
        bgg_id = $gameId
        name = [string]$game.name
        current_rating = $currentRating
        num_plays = [int]$game.num_plays
        collection = $collection
        previously_owned = $previouslyOwned
        want_to_play = $wantToPlay
        want_to_buy = $wantToBuy
        collection_to_exit = $collectionToExit
        collection_status = $collectionStatus
        group_key = [string]$game.group_key
        year_published = [int]$game.year_published
        players = $game.players
        complexity = $game.complexity
        bgg_rating = $game.bgg_rating
        num_ratings = $game.num_ratings
        categories = @($game.categories)
        mechanics = @($game.mechanics)
        bgg_game_url = Get-BggGameUrl -GameId $gameId
        mapped_at = (Get-Date -Format 'o')
    }
}

$rankedMembership = foreach ($group in ($membership | Group-Object ranking_group)) {
    $ordered = @($group.Group | Sort-Object @{ Expression = { if ($null -eq $_.rank_in_tier -or $_.rank_in_tier -eq '') { [int]::MaxValue } else { [int]$_.rank_in_tier } } }, @{ Expression = { [double]$_.current_rating }; Descending = $true }, @{ Expression = { [int]$_.num_plays }; Descending = $true }, name)
    $index = 0
    foreach ($item in $ordered) {
        $index++
        if (Test-IsNonRankedTier -Tier ([string]$item.tier)) {
            $item.rank_in_tier = $null
        } elseif ($ForceRebuildRanks -or $null -eq $item.rank_in_tier -or $item.rank_in_tier -eq '') {
            $item.rank_in_tier = $index
        }
        $item
    }
}

$rankedMembership = @($rankedMembership | Sort-Object tier_sort, @{ Expression = { [int]$_.source_bucket }; Descending = $true }, @{ Expression = { [int]$_.rank_in_tier } }, name)

$tierSummaries = foreach ($tier in (Get-TierOrder)) {
    $items = @($rankedMembership | Where-Object { $_.tier -eq $tier })
    if ($items.Count -eq 0) {
        continue
    }

    [pscustomobject]@{
        tier = $tier
        tier_sort = Get-TierSortWeight -Tier $tier
        count = $items.Count
        source_buckets = @($items | Group-Object source_bucket | Sort-Object Name -Descending | ForEach-Object {
            [pscustomobject]@{
                bucket = [int]$_.Name
                count = $_.Count
            }
        })
    }
}

$tierEngineExport = $rankedMembership | Select-Object tier, source_bucket, rank_in_tier, bgg_id, name, current_rating, num_plays, collection, previously_owned, want_to_play, want_to_buy, collection_to_exit, collection_status, players, complexity, bgg_rating, bgg_game_url

Write-JsonFile -Path $MembershipPath -Value $rankedMembership
Write-JsonFile -Path $TiersPath -Value $tierSummaries
Write-JsonFile -Path $TierExportJson -Value $tierEngineExport

$csvParent = Split-Path -Path $TierExportCsv -Parent
if ($csvParent -and -not (Test-Path $csvParent)) {
    New-Item -ItemType Directory -Path $csvParent -Force | Out-Null
}
$tierEngineExport | Export-Csv -Path $TierExportCsv -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    MembershipPath = $MembershipPath
    TiersPath = $TiersPath
    TierExportJson = $TierExportJson
    TierExportCsv = $TierExportCsv
    GamesMapped = $rankedMembership.Count
}
