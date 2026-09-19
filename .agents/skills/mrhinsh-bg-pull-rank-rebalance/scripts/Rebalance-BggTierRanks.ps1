[CmdletBinding()]
param(
    [string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$EquivalentGamesPath = '.\data\working\canonical\equivalent-games.json',
    [string]$RankOrderPath = '.\data\working\ranking\rank-order.json',
    [string]$PendingRatingUpdatesPath = '.\data\publish\queue\pending-rating-updates.json',
    [string]$ImportPath,
    [switch]$QueueOnly
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/ranking/rebalance/Rebalance-BggTierRanks.ps1') @PSBoundParameters
