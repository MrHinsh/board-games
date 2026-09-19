[CmdletBinding()]
param(
    [string]$InputPath = '.\data\working\canonical\games.json',
    [string]$OutDir = '.\data\reports\ranking',
    [string]$UnratedPath = '.\data\working\unrated\intake.json',
    [string]$UnratedRankedPath = '.\data\working\unrated\intake-ranked.json',
    [string]$GroupField = 'group_key'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/ranking/stackrank/Export-BggStackRank.ps1') @PSBoundParameters
