param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptPath=Join-Path $PSScriptRoot '../expansions/run.ps1'
$command=Get-Command $scriptPath
foreach ($parameter in @('CanonicalPath','CacheDir','OutDir','IncludeFanExpansions','IncludePromos','Tiers')) {
    if (-not $command.Parameters.ContainsKey($parameter)) { throw "Missing discovery contract: $parameter" }
}
# Discovery must not invoke preference mutations or publishing. This is a boundary
# check, not a claim that the live BGG expansion fetch has been exercised.
$text=Get-Content $scriptPath -Raw
if ($text -match 'Rebalance-BggTierRanks|Apply-BggTierMoves|Sync-BggRatingQueue|Set-BggPersonalRating') { throw 'Discovery crossed into preference mutation/publishing.' }
Write-Host 'What Am I Missing: discovery entrypoint and advisory boundary passed (no live fetch).'
