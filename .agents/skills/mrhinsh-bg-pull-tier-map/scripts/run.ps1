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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'Map-BggTiers.ps1'
& $scriptPath -CanonicalPath $CanonicalPath -EquivalentGamesPath $EquivalentGamesPath -MembershipPath $MembershipPath -TiersPath $TiersPath -TierExportJson $TierExportJson -TierExportCsv $TierExportCsv -IncludeUnrated:$IncludeUnrated -ForceRebuildRanks:$ForceRebuildRanks
