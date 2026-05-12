[CmdletBinding()]
param(
    [string]$UnratedPath = '.\data\working\unrated\intake-ranked.json',
    [string]$PlayedPath = '.\data\working\canonical\games.json',
    [string]$UnratedGamesPath = '.\data\working\unrated\intake.json'
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

if (-not (Test-Path $UnratedPath)) {
    throw "Unrated file not found: $UnratedPath"
}

if (-not (Test-Path $PlayedPath)) {
    throw "Played file not found: $PlayedPath"
}

# Read the edited unrated file to extract new ratings
$unratedData = @(Get-Content -Path $UnratedPath -Raw | ConvertFrom-Json)
$played = @(Get-Content -Path $PlayedPath -Raw | ConvertFrom-Json)

# Build a map of bgg_id -> new_rating from unrated file
$updates = @{}
$noteUpdates = @{}
foreach ($item in $unratedData) {
    if ($item.current_rating -and [double]$item.current_rating -gt 0) {
        $updates[[int]$item.bgg_id] = [double]$item.current_rating
    }

    if ($item.PSObject.Properties['notes'] -and -not [string]::IsNullOrWhiteSpace([string]$item.notes)) {
        $noteUpdates[[int]$item.bgg_id] = ([string]$item.notes).Trim()
    }
}

Write-Host "Found $($updates.Count) newly-rated games in intake-ranked.json" -ForegroundColor Cyan

# Apply ratings to played-games.json
$updatedPlayed = 0
$sampleUpdates = @()
foreach ($item in $played) {
    $id = [int]$item.bgg_id
    if ($updates.ContainsKey($id)) {
        $oldRating = $item.rating
        $item.rating = $updates[$id]
        $updatedPlayed++
        if ($sampleUpdates.Count -lt 3) {
            $sampleUpdates += [pscustomobject]@{
                Name = $item.name
                OldRating = $oldRating
                NewRating = $updates[$id]
                Plays = $item.num_plays
            }
        }
    }

    if ($noteUpdates.ContainsKey($id)) {
        Set-ObjectProperty -Target $item -Name 'notes' -Value ([string]$noteUpdates[$id])
    }
}

$played | ConvertTo-Json -Depth 10 | Set-Content -Path $PlayedPath -Encoding UTF8
Write-Host "✓ Applied $updatedPlayed ratings to played-games.json" -ForegroundColor Green

# Apply ratings to unrated-games.json if it exists
$updatedUnrated = 0
if (Test-Path $UnratedGamesPath) {
    $unratedGames = @(Get-Content -Path $UnratedGamesPath -Raw | ConvertFrom-Json)
    foreach ($item in $unratedGames) {
        $id = [int]$item.bgg_id
        if ($updates.ContainsKey($id)) {
            $item.current_rating = $updates[$id]
            $updatedUnrated++
        }

        if ($noteUpdates.ContainsKey($id)) {
            Set-ObjectProperty -Target $item -Name 'notes' -Value ([string]$noteUpdates[$id])
        }
    }
    $unratedGames | ConvertTo-Json -Depth 10 | Set-Content -Path $UnratedGamesPath -Encoding UTF8
    Write-Host "✓ Applied $updatedUnrated ratings to unrated-games.json" -ForegroundColor Green
}

Write-Host ""
Write-Host "Import Summary:" -ForegroundColor Cyan
$sampleUpdates | Format-Table Name, OldRating, NewRating, Plays -AutoSize

# Report total games with ratings
$totalRated = @($played | Where-Object { [double]$_.rating -gt 0 }).Count
Write-Host ""
Write-Host "Total rated games in games.json: $totalRated / $($played.Count)" -ForegroundColor Cyan
