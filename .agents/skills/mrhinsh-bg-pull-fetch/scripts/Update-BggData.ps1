[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,

    [ValidateSet('none', 'players', 'complexity', 'year')]
    [string]$GroupBy = 'players',

    [int]$Top = 10,
    [switch]$IncludeExpansions,

    [switch]$BuildRatingSheet = $true,

    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$RankingOutDir = '.\data\reports\ranking',
    [string]$TopOutDir = '.\data\reports\top'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../workflows/Update-BggData.ps1') @PSBoundParameters
