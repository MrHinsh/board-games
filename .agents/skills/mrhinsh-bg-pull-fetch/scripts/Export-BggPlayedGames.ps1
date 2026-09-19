[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [string]$OutDir = '.\\data\\working\\canonical',
    [string]$OutCsvPath = '.\\data\\reports\\ranking\\played-games.csv',
    [switch]$IncludeExpansions,
    [ValidateSet('none', 'players', 'complexity', 'year')]
    [string]$GroupBy = 'players',
    [switch]$EnrichWithDetails = $true
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/bgg-integration/collection-fetch/Export-BggPlayedGames.ps1') @PSBoundParameters
