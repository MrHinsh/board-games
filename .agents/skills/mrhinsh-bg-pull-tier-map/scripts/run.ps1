[CmdletBinding()]
param(
	[string]$CanonicalPath = '.\data\working\canonical\games.json',
	[string]$EquivalentGamesPath = '.\data\working\canonical\equivalent-games.json',
	[string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
	[string]$TiersPath = '.\data\working\ranking\tiers.json',
	[string]$TierExportJson = '.\data\publish\tiers\tier-engine-export.json',
	[string]$TierExportCsv = '.\data\publish\tiers\tier-engine-export.csv',
	[switch]$IncludeUnrated,
	[switch]$ForceRebuildRanks
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/tiers/membership/run.ps1') @PSBoundParameters
