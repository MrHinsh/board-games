[CmdletBinding()]
param(
    [string]$InputPath = '.\data\working\unrated\intake-ranked.json',
    [string]$OutPath = '.\data\publish\sheets\bgg-rating-upload-sheet.csv',
    [string]$CanonicalPath = '.\data\working\canonical\games.json'
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/tiers/rating-sheet/New-BggRatingUploadSheet.ps1') @PSBoundParameters
