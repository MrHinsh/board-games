[CmdletBinding()]
param(
    [string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
    [string]$QueuePath = '.\data\publish\queue\pending-tier-moves.json',
    [string]$ImportPath,
    [int]$GameId,
    [ValidateSet('S', 'A', 'B', 'C', 'D', 'F', 'U')]
    [string]$Tier,
    [int]$SourceBucket = -1,
    [string]$Notes = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\..\mrhinsh-bg-shared\scripts\BggTierHelpers.ps1"

function Resolve-SourceBucket {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tier,
        [int]$SourceBucket = -1
    )

    switch ($Tier) {
        'S' { return 10 }
        'A' { return 9 }
        'B' { return 8 }
        'C' { return 7 }
        'D' { return 6 }
        'U' { return 0 }
        'F' {
            if ($SourceBucket -lt 1 -or $SourceBucket -gt 5) {
                return 5
            }
            return $SourceBucket
        }
        default {
            throw "Unsupported tier: $Tier"
        }
    }
}

$membership = @(Read-JsonFile -Path $MembershipPath -Default @())
if ($membership.Count -eq 0) {
    throw "Tier membership file is empty or missing: $MembershipPath"
}

$membershipById = @{}
foreach ($item in $membership) {
    $membershipById[[int]$item.bgg_id] = $item
}

$moves = [System.Collections.Generic.List[object]]::new()
if ($GameId -gt 0 -and $Tier) {
    [void]$moves.Add([pscustomobject]@{
        bgg_id = $GameId
        tier = $Tier
        source_bucket = $SourceBucket
        notes = $Notes
    })
}

if ($ImportPath) {
    foreach ($item in @(Import-TabularData -Path $ImportPath)) {
        [void]$moves.Add($item)
    }
} elseif (Test-Path $QueuePath) {
    foreach ($item in @(Read-JsonFile -Path $QueuePath -Default @())) {
        [void]$moves.Add($item)
    }
}

$applied = [System.Collections.Generic.List[object]]::new()
foreach ($move in $moves) {
    $moveId = [int]$move.bgg_id
    if (-not $membershipById.ContainsKey($moveId)) {
        continue
    }

    $targetTier = [string]$move.tier
    if ([string]::IsNullOrWhiteSpace($targetTier)) {
        continue
    }

    $resolvedBucket = Resolve-SourceBucket -Tier $targetTier -SourceBucket ([int]$move.source_bucket)
    $entry = $membershipById[$moveId]
    $entry.tier = $targetTier
    $entry.tier_sort = Get-TierSortWeight -Tier $targetTier
    $entry.source_bucket = $resolvedBucket
    $newRankingGroup = Get-TierRankingGroupKey -Tier $targetTier -SourceBucket $resolvedBucket
    if ($entry.PSObject.Properties['ranking_group']) {
        $entry.ranking_group = $newRankingGroup
    } else {
        $entry | Add-Member -NotePropertyName ranking_group -NotePropertyValue $newRankingGroup
    }
    $entry.rank_in_tier = $null
    if ($entry.PSObject.Properties['moved_at']) {
        $entry.moved_at = (Get-Date -Format 'o')
    } else {
        $entry | Add-Member -NotePropertyName moved_at -NotePropertyValue (Get-Date -Format 'o')
    }

    if ($entry.PSObject.Properties['move_notes']) {
        $entry.move_notes = [string]$move.notes
    } else {
        $entry | Add-Member -NotePropertyName move_notes -NotePropertyValue ([string]$move.notes)
    }

    [void]$applied.Add([pscustomobject]@{
        bgg_id = $moveId
        name = [string]$entry.name
        tier = $targetTier
        source_bucket = $resolvedBucket
    })
}

if ($applied.Count -eq 0) {
    if (-not $ImportPath -and (Test-Path $QueuePath)) {
        Write-JsonFile -Path $QueuePath -Value @()
    }

    [pscustomobject]@{
        AppliedMoves = 0
        MembershipPath = $MembershipPath
        QueuePath = $QueuePath
    }
    return
}

$rebuilt = foreach ($group in ($membershipById.Values | Group-Object ranking_group)) {
    $ordered = @($group.Group | Sort-Object @{ Expression = { [double]$_.current_rating }; Descending = $true }, @{ Expression = { [int]$_.num_plays }; Descending = $true }, name)
    $index = 0
    foreach ($item in $ordered) {
        $index++
        if ($null -eq $item.rank_in_tier -or $item.rank_in_tier -eq '') {
            $item.rank_in_tier = $index
        }
        $item
    }
}

$rebuilt = @($rebuilt | Sort-Object tier_sort, @{ Expression = { [int]$_.source_bucket }; Descending = $true }, @{ Expression = { [int]$_.rank_in_tier } }, name)
Write-JsonFile -Path $MembershipPath -Value $rebuilt

if (-not $ImportPath) {
    Write-JsonFile -Path $QueuePath -Value @()
}

[pscustomobject]@{
    AppliedMoves = $applied.Count
    MembershipPath = $MembershipPath
    QueuePath = $QueuePath
}
