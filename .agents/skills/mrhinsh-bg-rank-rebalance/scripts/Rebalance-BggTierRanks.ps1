[CmdletBinding()]
param(
    [string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$RankOrderPath = '.\data\working\ranking\rank-order.json',
    [string]$PendingRatingUpdatesPath = '.\data\publish\queue\pending-rating-updates.json',
    [string]$ImportPath,
    [switch]$QueueOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\..\mrhinsh-bg-shared\scripts\BggTierHelpers.ps1"

$membership = @(Read-JsonFile -Path $MembershipPath -Default @())
if ($membership.Count -eq 0) {
    throw "Tier membership file is empty or missing: $MembershipPath"
}

$canonical = @(Read-JsonFile -Path $CanonicalPath -Default @())
$canonicalById = @{}
foreach ($game in $canonical) {
    $canonicalById[[int]$game.bgg_id] = $game
}

$importedById = @{}
if ($ImportPath) {
    if (Test-Path $ImportPath) {
        $perGroupSequence = @{}
        foreach ($item in @(Import-TabularData -Path $ImportPath)) {
            $id = [int]$item.bgg_id
            if ($id -le 0) {
                continue
            }

            $tier = if ($item.PSObject.Properties['tier']) { [string]$item.tier } else { '' }
            $bucket = if ($item.PSObject.Properties['source_bucket']) { [int]$item.source_bucket } else { -1 }
            $groupKey = Get-TierRankingGroupKey -Tier $tier -SourceBucket $bucket
            if (-not $perGroupSequence.ContainsKey($groupKey)) {
                $perGroupSequence[$groupKey] = 0
            }
            $perGroupSequence[$groupKey]++

            $rank = $null
            if ($item.PSObject.Properties['rank_in_tier'] -and $item.rank_in_tier -ne '') {
                $rank = [int]$item.rank_in_tier
            } elseif ($item.PSObject.Properties['sort_order'] -and $item.sort_order -ne '') {
                $rank = [int]$item.sort_order
            } else {
                $rank = [int]$perGroupSequence[$groupKey]
            }

            $importedById[$id] = $rank
        }
    } else {
        Write-Warning "Import file not found. Continuing without imported rank order: $ImportPath"
    }
}

$rankOrder = [System.Collections.Generic.List[object]]::new()
foreach ($group in ($membership | Where-Object { -not (Test-IsNonRankedTier -Tier ([string]$_.tier)) } | Group-Object ranking_group)) {
    $ordered = @($group.Group | Sort-Object @{ Expression = {
                    if ($importedById.ContainsKey([int]$_.bgg_id)) { $importedById[[int]$_.bgg_id] }
                    elseif ($null -eq $_.rank_in_tier -or $_.rank_in_tier -eq '') { [int]::MaxValue }
                    else { [int]$_.rank_in_tier }
                } }, @{ Expression = { [double]$_.current_rating }; Descending = $true }, @{ Expression = { [int]$_.num_plays }; Descending = $true }, name)
    $groupCount = $ordered.Count
    $index = 0
    foreach ($item in $ordered) {
        $index++
        if ($item.PSObject.Properties['rank_in_tier']) {
            $item.rank_in_tier = $index
        } else {
            $item | Add-Member -NotePropertyName rank_in_tier -NotePropertyValue $index
        }

        $proposedRating = Convert-TierRankToBggRating -Tier ([string]$item.tier) -SourceBucket ([int]$item.source_bucket) -RankInTier $index -TierCount $groupCount
        if ($item.PSObject.Properties['proposed_rating']) {
            $item.proposed_rating = $proposedRating
        } else {
            $item | Add-Member -NotePropertyName proposed_rating -NotePropertyValue $proposedRating
        }
        [void]$rankOrder.Add([pscustomobject]@{
            tier = [string]$item.tier
            source_bucket = [int]$item.source_bucket
            rank_in_tier = $index
            tier_count = $groupCount
            bgg_id = [int]$item.bgg_id
            name = [string]$item.name
            current_rating = [double]$item.current_rating
            proposed_rating = [double]$item.proposed_rating
            num_plays = [int]$item.num_plays
            delta = [math]::Round(([double]$item.proposed_rating - [double]$item.current_rating), 3)
        })
    }
}

$nonRanked = @($membership | Where-Object { Test-IsNonRankedTier -Tier ([string]$_.tier) })
foreach ($item in $nonRanked) {
    $nonRankedProposedRating = if ([string]$item.tier -eq 'U') { 0.0 } else { [double]$item.current_rating }

    if ($item.PSObject.Properties['rank_in_tier']) {
        $item.rank_in_tier = $null
    } else {
        $item | Add-Member -NotePropertyName rank_in_tier -NotePropertyValue $null
    }

    if ($item.PSObject.Properties['proposed_rating']) {
        $item.proposed_rating = $nonRankedProposedRating
    } else {
        $item | Add-Member -NotePropertyName proposed_rating -NotePropertyValue $nonRankedProposedRating
    }
}

$membership = @($membership | Sort-Object tier_sort, @{ Expression = { [int]$_.source_bucket }; Descending = $true }, @{ Expression = { if ($null -eq $_.rank_in_tier) { [int]::MaxValue } else { [int]$_.rank_in_tier } } }, name)
Write-JsonFile -Path $MembershipPath -Value $membership
Write-JsonFile -Path $RankOrderPath -Value @($rankOrder)

$pendingUpdates = @($rankOrder | Where-Object { [math]::Abs([double]$_.delta) -gt 0.0005 } | ForEach-Object {
    [pscustomobject]@{
        bgg_id = [int]$_.bgg_id
        name = [string]$_.name
        tier = [string]$_.tier
        source_bucket = [int]$_.source_bucket
        rank_in_tier = [int]$_.rank_in_tier
        current_rating = [double]$_.current_rating
        target_rating = [double]$_.proposed_rating
        delta = [double]$_.delta
        status = 'queued'
    }
})
Write-JsonFile -Path $PendingRatingUpdatesPath -Value $pendingUpdates

if (-not $QueueOnly) {
    foreach ($row in $rankOrder) {
        $id = [int]$row.bgg_id
        if ($canonicalById.ContainsKey($id)) {
            $canonicalById[$id].rating = [double]$row.proposed_rating
        }
    }

    foreach ($item in ($nonRanked | Where-Object { $_.tier -eq 'U' })) {
        $id = [int]$item.bgg_id
        if ($canonicalById.ContainsKey($id)) {
            $canonicalById[$id].rating = 0.0
        }
    }

    $updatedCanonical = @($canonicalById.Values | Sort-Object group_key, name)
    Write-JsonFile -Path $CanonicalPath -Value $updatedCanonical
}

[pscustomobject]@{
    MembershipPath = $MembershipPath
    RankOrderPath = $RankOrderPath
    PendingRatingUpdatesPath = $PendingRatingUpdatesPath
    RatingsQueued = $pendingUpdates.Count
    CanonicalUpdated = (-not $QueueOnly)
}
