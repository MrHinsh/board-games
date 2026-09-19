param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../collection-fetch/CollectionFetchHelpers.ps1')

$dir = Join-Path $FixtureRoot 'collection-equivalent-fallback'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$equivalentPath = Join-Path $dir 'equivalent-games.json'
@([pscustomobject]@{primary_bgg_id=270239;linked_bgg_ids=@(367893)}) |
    ConvertTo-Json -Depth 4 | Set-Content $equivalentPath

$ownedItems = @(
    [pscustomobject]@{objectid=367893;name='Moonrakers: Titan Edition (w/o base game)'},
    [pscustomobject]@{objectid=340035;name='Arbitrary Expansion'},
    [pscustomobject]@{objectid=999999;name='Unrelated Compilation'}
)

$selected = @(Select-ExplicitEquivalentOwnedItems -Items $ownedItems -EquivalentGamesPath $equivalentPath)
if ($selected.Count -ne 1 -or [int]$selected[0].objectid -ne 367893) {
    throw 'Owned fallback must admit only IDs from the explicit equivalence registry.'
}

$withExpansions = @(Select-ExplicitEquivalentOwnedItems -Items $ownedItems `
    -EquivalentGamesPath $equivalentPath -IncludeExpansions)
if ($withExpansions.Count -ne 0) {
    throw 'Owned equivalence fallback must be skipped when expansions are included.'
}

Write-Host 'BGG Integration: owned compilation fallback is explicit and excludes arbitrary expansions.'
