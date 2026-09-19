[CmdletBinding()]
param(
    [string]$UnratedPath = '.\data\working\unrated\intake-ranked.json',
    [string]$PlayedPath = '.\data\working\canonical\games.json',
    [string]$UnratedGamesPath = '.\data\working\unrated\intake.json'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/tiers/rating-intake/Import-BggRatingsFromUnrated.ps1') @PSBoundParameters
