[CmdletBinding()]
param(
    [string]$InputPath = '.\data\working\unrated\intake-ranked.json',
    [string]$OutPath = '.\data\publish\sheets\bgg-rating-upload-sheet.csv'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $InputPath)) {
    throw "Input file not found: $InputPath"
}

$outDir = Split-Path -Path $OutPath -Parent
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$items = @(Get-Content -Path $InputPath -Raw | ConvertFrom-Json)

if ($items.Count -eq 0) {
    Write-Warning 'No unrated games found in input file.'
    return
}

$sheet = $items |
    Sort-Object @{ Expression = { [int]$_.num_plays }; Descending = $true }, @{ Expression = { $_.name } } |
    Select-Object @{ Name = 'bgg_id'; Expression = { $_.bgg_id } },
                  @{ Name = 'name'; Expression = { $_.name } },
                  @{ Name = 'num_plays'; Expression = { $_.num_plays } },
                  @{ Name = 'current_rating'; Expression = { $_.current_rating } },
                  @{ Name = 'bgg_comment'; Expression = { if ($_.PSObject.Properties['bgg_comment']) { $_.bgg_comment } else { '' } } },
                  @{ Name = 'notes'; Expression = { if ($_.PSObject.Properties['notes']) { $_.notes } else { '' } } },
                  @{ Name = 'new_rating'; Expression = { '' } },
                  @{ Name = 'bgg_game_url'; Expression = { "https://boardgamegeek.com/boardgame/$($_.bgg_id)" } }

$sheet | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    Rows = $sheet.Count
    Csv = $OutPath
}