param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixture=Join-Path $FixtureRoot 'composition'
foreach ($path in @('systems/bgg-integration/pull/run.ps1','workflows/Rebuild-BoardGames.ps1','workflows/Refresh-BoardGames.ps1')) {
    $target=Join-Path $fixture $path
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo $path) -Destination $target
}
$stages=[ordered]@{
    'systems/bgg-integration/collection-fetch/run.ps1'='fetch'
    'systems/bgg-integration/reconcile/run.ps1'='reconcile'
    'systems/ranking/stackrank/Export-BggStackRank.ps1'='rank'
    'systems/tiers/rating-sheet/New-BggRatingUploadSheet.ps1'='sheet'
    'systems/ranking/top-report/Export-BggTop10.ps1'='report'
    'systems/tiers/membership/run.ps1'='tiers'
    'systems/ranking/external-ordering/run.ps1'='ordering'
    'systems/tiers/moves/run.ps1'='moves'
    'systems/ranking/rebalance/run.ps1'='rebalance'
}
foreach ($path in $stages.Keys) {
    $target=Join-Path $fixture $path
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    $stub=@'
param($Username,$Endpoint,$ApiKey,$Cookie,[switch]$IncludeExpansions,$SnapshotPath,$CanonicalPath,$PubMeepleInputDir,$ImportPath)
$global:BgBoundaryCalls.Add([pscustomobject]@{ Stage='STAGE_NAME'; Parameters=@{} + $PSBoundParameters })
if ('STAGE_NAME' -eq 'fetch') { 'snapshot-fixture.json' } else { [pscustomobject]@{ Stage='STAGE_NAME' } }
'@
    $stub.Replace('STAGE_NAME',$stages[$path]) | Set-Content $target
}
$global:BgBoundaryCalls=[Collections.Generic.List[object]]::new()
try {
    & "$fixture/systems/bgg-integration/pull/run.ps1" -Username 'FixtureUser' -IncludeExpansions | Out-Null
    if (($global:BgBoundaryCalls.Stage -join ',') -ne 'fetch,reconcile') { throw 'Pull invoked another system.' }
    if ($global:BgBoundaryCalls[1].Parameters.SnapshotPath -ne 'snapshot-fixture.json') { throw 'Pull did not reconcile the fetched snapshot.' }
    if (-not $global:BgBoundaryCalls[0].Parameters.IncludeExpansions) { throw 'Pull lost an explicit switch.' }
    $global:BgBoundaryCalls.Clear()
    & "$fixture/workflows/Rebuild-BoardGames.ps1" | Out-Null
    if (($global:BgBoundaryCalls.Stage -join ',') -ne 'rank,sheet,report,tiers,ordering,moves,rebalance') { throw 'Rebuild crossed boundaries or changed stage order.' }
    if (-not $global:BgBoundaryCalls[2].Parameters.ContainsKey('CanonicalPath')) { throw 'Rebuild top report can hit the network.' }
    if ($global:BgBoundaryCalls[4].Parameters.PubMeepleInputDir -match 'data/raw') { throw 'Rebuild would regenerate immutable raw files.' }
    $global:BgBoundaryCalls.Clear()
    & "$fixture/workflows/Refresh-BoardGames.ps1" -Username 'FixtureUser' | Out-Null
    if (($global:BgBoundaryCalls.Stage -join ',') -ne 'fetch,reconcile,rank,sheet,report,tiers,ordering,moves,rebalance') { throw 'Refresh composition regressed.' }
    "throw 'Fixture fetch failure'" | Set-Content "$fixture/systems/bgg-integration/collection-fetch/run.ps1"
    $global:BgBoundaryCalls.Clear()
    $failed=$false
    try { & "$fixture/workflows/Refresh-BoardGames.ps1" -Username FixtureUser | Out-Null } catch { $failed=$true }
    if (-not $failed -or $global:BgBoundaryCalls.Count -ne 0) { throw 'Refresh continued after fetch failure.' }
} finally {
    Remove-Variable BgBoundaryCalls -Scope Global
}
Write-Host 'Workflows: Pull isolation, local Rebuild, Refresh ordering and stop-on-failure passed.'
