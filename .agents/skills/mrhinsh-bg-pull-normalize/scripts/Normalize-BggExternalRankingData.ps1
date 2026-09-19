[CmdletBinding()]
param(
    [string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$UnratedRankedPath = '.\data\working\unrated\intake-ranked.json',
    [string]$TierExportDir = '.\data\publish\tiers',
    [string]$RankingExportDir = '.\data\publish\ranking',
    [string]$TierImportPath = '.\data\publish\tiers\tier-engine-import.csv',
    [string]$RankingImportDir = '.\data\publish\ranking\import',
    [string]$PubMeepleInputDir = '.\data\raw\pubmeeple\in',
    [string]$PubMeepleOutputDir = '.\data\raw\pubmeeple\out',
    [string]$PendingTierMovesPath = '.\data\publish\queue\pending-tier-moves.json',
    [string]$NormalizedRankingImportPath = '.\data\working\ranking\external-ordering.json'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/ranking/external-ordering/Normalize-BggExternalRankingData.ps1') @PSBoundParameters
