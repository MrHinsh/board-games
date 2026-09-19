[CmdletBinding()]
param(
    [string]$SheetPath = '.\data\publish\sheets\bgg-rating-upload-sheet.csv',
    [string]$UnratedPath = '.\data\working\unrated\intake-ranked.json',
    [string]$PlayedPath = '.\data\working\canonical\games.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$importScript = Join-Path $PSScriptRoot 'Import-BggRatingSheet.ps1'
if (-not (Test-Path $importScript)) {
    throw "Missing script: $importScript"
}

& $importScript -SheetPath $SheetPath -UnratedPath $UnratedPath -PlayedPath $PlayedPath
