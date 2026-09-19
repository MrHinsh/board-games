param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$dir=Join-Path $FixtureRoot 'prediction'
New-Item -ItemType Directory -Path $dir | Out-Null
@'
| Host 01: | Alice |
| Game 1: | Fixture Game |
| Game 2: | Another Game |
'@ | Set-Content "$dir/sheet.txt"
& (Join-Path $PSScriptRoot '../club-nominations/Parse-Nominations.ps1') -SheetDumpPath "$dir/sheet.txt" -OutPath "$dir/parsed.csv" | Out-Null
$rows=@(Import-Csv "$dir/parsed.csv")
if ($rows.Count -ne 2 -or $rows[0].host -ne 'Alice' -or $rows[0].game_raw -ne 'Fixture Game') { throw 'Nomination parsing regressed.' }
. (Join-Path $PSScriptRoot '../model/BggTasteModel.ps1')
if (-not (Get-Command New-BggTasteModel -ErrorAction SilentlyContinue)) { throw 'Taste model did not load.' }
. (Join-Path $PSScriptRoot '../club-nominations/Update-DesignerIndex.ps1')
$indexPath = Join-Path $dir 'designer-index.json'
'{"1":["Existing Designer"],"99":["Historical Designer"]}' | Set-Content $indexPath
$lastFullRefresh = (Get-Date).AddDays(-29)
(Get-Item $indexPath).LastWriteTime = $lastFullRefresh
$games = @(
    [pscustomobject]@{ bgg_id = 1; num_plays = 1 },
    [pscustomobject]@{ bgg_id = 2; num_plays = 2 },
    [pscustomobject]@{ bgg_id = 3; num_plays = 0 },
    [pscustomobject]@{ bgg_id = 4; num_plays = 1 }
)
$script:requestedIds = @()
$fetch = {
    param($ids, $endpoint)
    $script:requestedIds += @($ids)
    foreach ($id in $ids) {
        [pscustomobject]@{ id = $id; designer = $(if ($id -eq 4) { '' } else { 'New Designer' }) }
    }
}
$index = Update-BggDesignerIndex -Games $games -TrainingGames @($games[0]) -Path $indexPath -FetchDetails $fetch
if (@($script:requestedIds | Sort-Object).Count -ne 2 -or $script:requestedIds -contains 1 -or $script:requestedIds -contains 3) {
    throw 'Designer index did not fetch exactly the missing played games.'
}
if ($index[1][0] -ne 'Existing Designer' -or $index[99][0] -ne 'Historical Designer' -or $index[2][0] -ne 'New Designer' -or -not $index.ContainsKey(4) -or @($index[4]).Count -ne 0 -or $index.ContainsKey(3)) {
    throw 'Designer index lost cached data, ignored a played game, or included an unplayed unrated game.'
}
if ([math]::Abs(((Get-Item $indexPath).LastWriteTime - $lastFullRefresh).TotalSeconds) -gt 2) {
    throw 'Incremental designer fetch postponed the full refresh date.'
}
$before = Get-Content $indexPath -Raw
try {
    Update-BggDesignerIndex -Games $games -TrainingGames @($games[0]) -Path $indexPath -Refresh -FetchDetails { @() } | Out-Null
    throw 'Incomplete BGG response was accepted.'
} catch {
    if ($_.Exception.Message -eq 'Incomplete BGG response was accepted.') { throw }
}
if ((Get-Content $indexPath -Raw) -ne $before) { throw 'Incomplete BGG response changed the designer cache.' }
$refreshed = Update-BggDesignerIndex -Games $games -TrainingGames @($games[0]) -Path $indexPath -Refresh -FetchDetails $fetch
if ($refreshed[99][0] -ne 'Historical Designer' -or $refreshed[1][0] -ne 'New Designer' -or $refreshed[2][0] -ne 'New Designer' -or -not $refreshed.ContainsKey(4)) {
    throw 'Successful designer index refresh did not preserve historical entries and refresh current games.'
}
$script:requestedIds = @()
(Get-Item $indexPath).LastWriteTime = (Get-Date).AddDays(-31)
$aged = Update-BggDesignerIndex -Games $games -TrainingGames @($games[0]) -Path $indexPath -MaxAgeDays 30 -FetchDetails $fetch
if (@($script:requestedIds).Count -ne 3 -or $aged[99][0] -ne 'Historical Designer') {
    throw 'Expired designer index did not refresh all current games while retaining historical entries.'
}
Write-Host 'Prediction: nomination parsing, designer index coverage, and pure model loading passed.'
