param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dir = Join-Path $FixtureRoot 'reconcile-relationships'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$canonicalPath = Join-Path $dir 'games.json'
$snapshotPath = Join-Path $dir 'snapshot.json'
$intakePath = Join-Path $dir 'intake.json'
$reportPath = Join-Path $dir 'report.json'

@([pscustomobject]@{
    group_key='2-4';bgg_id=1;name='Canonical Only';year_published=2020;rating=7.0;num_plays=1
}) | ConvertTo-Json -Depth 5 | Set-Content $canonicalPath

@([pscustomobject]@{
    bgg_id=2;name='Fresh Game';year_published=2024;rating=0.0;num_plays=1;collection=$false
    previously_owned=$false;want_to_play=$false;want_to_buy=$false;collection_to_exit=$false
    collection_status='NotOwned';players='2-4';complexity=2.5;bgg_rating=7.5;num_ratings=100
    categories=@();mechanics=@();reimplements=@(1);reimplemented_by=@(3);bgg_comment=''
}) | ConvertTo-Json -Depth 5 | Set-Content $snapshotPath
'[]' | Set-Content $intakePath

& (Join-Path $PSScriptRoot '../reconcile/run.ps1') -SnapshotPath $snapshotPath `
    -CanonicalPath $canonicalPath -IntakePath $intakePath -ReconcilePath $reportPath | Out-Null

$games = @(Get-Content $canonicalPath -Raw | ConvertFrom-Json)
$canonicalOnly = $games | Where-Object bgg_id -eq 1
$fresh = $games | Where-Object bgg_id -eq 2
if (-not $canonicalOnly.PSObject.Properties['reimplements'] -or @($canonicalOnly.reimplements).Count -ne 0) {
    throw 'Canonical-only game did not receive an empty reimplements array.'
}
if (-not $canonicalOnly.PSObject.Properties['reimplemented_by'] -or @($canonicalOnly.reimplemented_by).Count -ne 0) {
    throw 'Canonical-only game did not receive an empty reimplemented_by array.'
}
if (@($fresh.reimplements).Count -ne 1 -or [int]$fresh.reimplements[0] -ne 1) {
    throw 'Fresh reimplements relationship was not preserved.'
}
if (@($fresh.reimplemented_by).Count -ne 1 -or [int]$fresh.reimplemented_by[0] -ne 3) {
    throw 'Fresh reimplemented_by relationship was not preserved.'
}

Write-Host 'BGG Integration: reconcile preserves directional links and backfills canonical-only games.'
