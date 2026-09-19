[CmdletBinding()]
param(
	[string]$Username,
	[string]$Endpoint = 'https://boardgamegeek.com',
	[string]$Cookie,
	[string]$SessionFile = '.\.local\secrets\bgg-session.json',
	[string]$ReportPath = '.\data\reports\quality\duplicate-collection-report.json'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/bgg-integration/audit/run.ps1') @PSBoundParameters
