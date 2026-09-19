[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PubMeepleCsvPath,

    [Parameter(Mandatory = $true)]
    [string]$RankingCsvPath,

    [string]$ImportRankColumn = 'rank',
    [string]$ImportTitleColumn = 'item',
    [string]$RankingTitleColumn = 'name'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/ranking/external-ordering/Import-PubMeepleTierRanking.ps1') @PSBoundParameters
