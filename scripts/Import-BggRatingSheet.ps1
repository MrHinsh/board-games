[CmdletBinding()]
param(
    [string]$SheetPath = '.\output\bgg-rating-upload-sheet.csv',
    [string]$UnratedPath = '.\output\unrated-ranked-by-plays.json',
    [string]$PlayedPath = '.\output\played-games.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SheetPath)) {
    throw "Sheet file not found: $SheetPath"
}

if (-not (Test-Path $UnratedPath)) {
    throw "Unrated file not found: $UnratedPath"
}

if (-not (Test-Path $PlayedPath)) {
    throw "Played file not found: $PlayedPath"
}

$sheet = Import-Csv -Path $SheetPath
$updates = @{}

foreach ($row in $sheet) {
    if (-not $row.new_rating) {
        continue
    }

    $text = $row.new_rating.Trim()
    if ($text -eq '') {
        continue
    }

    $parsed = 0
    if (-not [int]::TryParse($text, [ref]$parsed)) {
        continue
    }

    if ($parsed -lt 1 -or $parsed -gt 10) {
        continue
    }

    $id = 0
    if (-not [int]::TryParse([string]$row.bgg_id, [ref]$id)) {
        continue
    }

    $updates[$id] = $parsed
}

$unrated = @(Get-Content -Path $UnratedPath -Raw | ConvertFrom-Json)
$played = @(Get-Content -Path $PlayedPath -Raw | ConvertFrom-Json)

$updatedUnrated = 0
foreach ($item in $unrated) {
    $id = [int]$item.bgg_id
    if ($updates.ContainsKey($id)) {
        $item.current_rating = [double]$updates[$id]
        $updatedUnrated++
    }
}

$updatedPlayed = 0
foreach ($item in $played) {
    $id = [int]$item.bgg_id
    if ($updates.ContainsKey($id)) {
        $item.rating = [double]$updates[$id]
        $updatedPlayed++
    }
}

$unrated | ConvertTo-Json -Depth 10 | Set-Content -Path $UnratedPath -Encoding UTF8
$played | ConvertTo-Json -Depth 10 | Set-Content -Path $PlayedPath -Encoding UTF8

[pscustomobject]@{
    SheetRows = @($sheet).Count
    RatingsToApply = $updates.Count
    UpdatedUnratedRows = $updatedUnrated
    UpdatedPlayedRows = $updatedPlayed
}