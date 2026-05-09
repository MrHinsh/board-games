[CmdletBinding()]
param(
    [string]$InputPath = '.\output\unrated-ranked-by-plays.json',
    [string]$OutPath = '.\output\bgg-rating-upload-sheet.csv'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $InputPath)) {
    throw "Input file not found: $InputPath"
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
                  @{ Name = 'new_rating'; Expression = { '' } },
                  @{ Name = 'bgg_game_url'; Expression = { "https://boardgamegeek.com/boardgame/$($_.bgg_id)" } }

$sheet | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    Rows = $sheet.Count
    Csv = $OutPath
}