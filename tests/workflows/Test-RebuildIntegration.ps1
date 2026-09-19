param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixture=Join-Path $FixtureRoot 'real-rebuild'
New-Item -ItemType Directory -Path $fixture | Out-Null
# Copy executable components into a disposable test harness, without Git or real
# collection data. Checkpoint paths then resolve inside the fixture too.
Copy-Item -LiteralPath "$repo/systems" -Destination "$fixture/systems" -Recurse
New-Item -ItemType Directory -Path "$fixture/workflows","$fixture/scripts","$fixture/data/working/canonical","$fixture/data/raw/pubmeeple/in" -Force | Out-Null
Copy-Item -LiteralPath "$repo/workflows/Rebuild-BoardGames.ps1" -Destination "$fixture/workflows/Rebuild-BoardGames.ps1"
Copy-Item -LiteralPath "$repo/scripts/Checkpoint-Canonical.ps1" -Destination "$fixture/scripts/Checkpoint-Canonical.ps1"
$games=@(foreach ($id in 1..3) {
    [pscustomobject]@{
        bgg_id=$id; name="Fixture $id"; group_key='2-4'; year_published=2020
        rating= $(if ($id -eq 1) {10} elseif ($id -eq 2) {9} else {0})
        num_plays=2; players='2-4'; complexity=3; bgg_rating=7; num_ratings=100
        categories=@(); mechanics=@(); collection=$true; bgg_comment=''; notes=''
    }
})
ConvertTo-Json -InputObject $games | Set-Content "$fixture/data/working/canonical/games.json"
'[]' | Set-Content "$fixture/data/working/canonical/equivalent-games.json"
'Existing immutable input' | Set-Content "$fixture/data/raw/pubmeeple/in/tier-S-ranking.txt"
$rawHash=(Get-FileHash "$fixture/data/raw/pubmeeple/in/tier-S-ranking.txt").Hash
Push-Location $fixture
try {
    & './workflows/Rebuild-BoardGames.ps1' | Out-Null
} finally { Pop-Location }
if ((Get-FileHash "$fixture/data/raw/pubmeeple/in/tier-S-ranking.txt").Hash -ne $rawHash) { throw 'Rebuild overwrote a raw input.' }
foreach ($relative in @(
    'data/reports/ranking/stackranked.json',
    'data/reports/top/top-10.json',
    'data/publish/sheets/bgg-rating-upload-sheet.csv',
    'data/working/ranking/rank-order.json',
    'data/publish/queue/pending-rating-updates.json',
    'data/publish/pubmeeple/in/tier-S-ranking.txt'
)) {
    if (-not (Test-Path "$fixture/$relative")) { throw "Rebuild failed to produce $relative" }
}
$final=@(Get-Content "$fixture/data/working/canonical/games.json" -Raw | ConvertFrom-Json)
if ($final.Count -ne 3 -or ($final | Where-Object bgg_id -eq 1).rating -ne 9.999 -or ($final | Where-Object bgg_id -eq 2).rating -ne 8.999) { throw 'Real Rebuild did not produce expected singleton tier ratings.' }
if (($final | Where-Object bgg_id -eq 3).rating -ne 0) { throw 'Rebuild rated the unrated fixture game.' }
Write-Host 'Rebuild integration: real stages produced expected artifacts/ratings and preserved raw input.'
