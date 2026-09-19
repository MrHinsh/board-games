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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'Rebalance-BggTierRanks.ps1'
& $scriptPath -MembershipPath $MembershipPath -CanonicalPath $CanonicalPath -EquivalentGamesPath $EquivalentGamesPath -RankOrderPath $RankOrderPath -PendingRatingUpdatesPath $PendingRatingUpdatesPath -ImportPath $ImportPath -QueueOnly:$QueueOnly
