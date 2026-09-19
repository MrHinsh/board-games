param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$dir = Join-Path $FixtureRoot 'tiers'
New-Item -ItemType Directory -Path $dir | Out-Null
$game = [pscustomobject]@{
    bgg_id=101; name='Fixture game'; group_key='2-4'; year_published=2020
    rating=9.5; num_plays=2; players='2-4'; complexity=3; bgg_rating=7; num_ratings=100
    categories=@(); mechanics=@(); collection=$true
}
ConvertTo-Json -InputObject @($game) | Set-Content "$dir/games.json"
'[]' | Set-Content "$dir/equivalent.json"
$argsForMap = @{
    CanonicalPath="$dir/games.json"; EquivalentGamesPath="$dir/equivalent.json"
    MembershipPath="$dir/membership.json"; TiersPath="$dir/tiers.json"
    TierExportJson="$dir/export.json"; TierExportCsv="$dir/export.csv"
}
& (Join-Path $PSScriptRoot '../membership/run.ps1') @argsForMap | Out-Null
$row = @(Get-Content "$dir/membership.json" -Raw | ConvertFrom-Json)[0]
if ($row.tier -ne 'S' -or $row.rank_in_tier -ne 1) { throw 'Initial tier mapping regressed.' }
# Explicit existing classification wins over a changed incoming numeric score.
$row.source_bucket=9; $row.tier='A'; $row.ranking_group='A|9'
ConvertTo-Json -InputObject @($row) | Set-Content "$dir/membership.json"
& (Join-Path $PSScriptRoot '../membership/run.ps1') @argsForMap | Out-Null
$row = @(Get-Content "$dir/membership.json" -Raw | ConvertFrom-Json)[0]
if ($row.tier -ne 'A' -or $row.rank_in_tier -ne 1) { throw 'Stored tier/order was not preserved.' }
Write-Host 'Tier: initial mapping and stored membership preservation passed.'
