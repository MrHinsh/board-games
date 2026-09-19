[CmdletBinding()]
param(
    [string]$SheetPath = '.\data\publish\sheets\bgg-rating-upload-sheet.csv',
    [string]$UnratedPath = '.\data\working\unrated\intake-ranked.json',
    [string]$PlayedPath = '.\data\working\canonical\games.json'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/tiers/rating-intake/Import-BggRatingSheet.ps1') @PSBoundParameters
