[CmdletBinding()]
param(
    [string]$SheetPath = '.\data\publish\sheets\bgg-rating-upload-sheet.csv',
    [string]$UnratedPath = '.\data\working\unrated\intake-ranked.json',
    [string]$PlayedPath = '.\data\working\canonical\games.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Value
    )

    $property = $Target.PSObject.Properties[$Name]
    if ($property) {
        $property.Value = $Value
    } else {
        $Target | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

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
$noteUpdates = @{}

foreach ($row in $sheet) {
    $id = 0
    if (-not [int]::TryParse([string]$row.bgg_id, [ref]$id)) {
        continue
    }

    if ($row.PSObject.Properties['notes']) {
        $noteText = [string]$row.notes
        if (-not [string]::IsNullOrWhiteSpace($noteText)) {
            $noteUpdates[$id] = $noteText.Trim()
        }
    }

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

    if ($noteUpdates.ContainsKey($id)) {
        Set-ObjectProperty -Target $item -Name 'notes' -Value ([string]$noteUpdates[$id])
    }
}

$updatedPlayed = 0
foreach ($item in $played) {
    $id = [int]$item.bgg_id
    if ($updates.ContainsKey($id)) {
        $item.rating = [double]$updates[$id]
        $updatedPlayed++
    }

    if ($noteUpdates.ContainsKey($id)) {
        Set-ObjectProperty -Target $item -Name 'notes' -Value ([string]$noteUpdates[$id])
    }
}

$unrated | ConvertTo-Json -Depth 10 | Set-Content -Path $UnratedPath -Encoding UTF8
$played | ConvertTo-Json -Depth 10 | Set-Content -Path $PlayedPath -Encoding UTF8

[pscustomobject]@{
    SheetRows = @($sheet).Count
    RatingsToApply = $updates.Count
    NotesToApply = $noteUpdates.Count
    UpdatedUnratedRows = $updatedUnrated
    UpdatedPlayedRows = $updatedPlayed
}