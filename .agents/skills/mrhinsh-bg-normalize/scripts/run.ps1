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

$scriptPath = Join-Path $PSScriptRoot 'Normalize-BggExternalRankingData.ps1'
& $scriptPath -MembershipPath $MembershipPath -TierExportDir $TierExportDir -RankingExportDir $RankingExportDir -TierImportPath $TierImportPath -RankingImportDir $RankingImportDir -PubMeepleInputDir $PubMeepleInputDir -PubMeepleOutputDir $PubMeepleOutputDir -PendingTierMovesPath $PendingTierMovesPath -NormalizedRankingImportPath $NormalizedRankingImportPath
