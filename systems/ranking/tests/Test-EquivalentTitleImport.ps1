param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dir = Join-Path $FixtureRoot 'equivalent-title-import'
$pubIn = Join-Path $dir 'pub-in'
$pubOut = Join-Path $dir 'pub-out'
$rankingOut = Join-Path $dir 'ranking-out'
$tierOut = Join-Path $dir 'tier-out'
New-Item -ItemType Directory -Path $pubIn,$pubOut,$rankingOut,$tierOut -Force | Out-Null

$membership = @(
    [pscustomobject]@{tier='S';source_bucket=10;ranking_group='S:10';rank_in_tier=2;bgg_id=224783;name='Vindication';current_rating=9.3;num_plays=2;collection=$true;previously_owned=$false;want_to_play=$false;want_to_buy=$false;collection_to_exit=$false;collection_status='Owned';players='2-5';complexity=3.1;bgg_rating=7.8;bgg_comment='';notes='';bgg_game_url='';linked_bgg_ids=@(224783,380707)},
    [pscustomobject]@{tier='S';source_bucket=10;ranking_group='S:10';rank_in_tier=1;bgg_id=1;name='Other Game';current_rating=9.5;num_plays=1;collection=$true;previously_owned=$false;want_to_play=$false;want_to_buy=$false;collection_to_exit=$false;collection_status='Owned';players='2';complexity=2.0;bgg_rating=8.0;bgg_comment='';notes='';bgg_game_url='';linked_bgg_ids=@(1)}
)
$canonical = @(
    [pscustomobject]@{bgg_id=224783;name='Vindication'},
    [pscustomobject]@{bgg_id=380707;name='Vindication: Archive of the Ancients'},
    [pscustomobject]@{bgg_id=1;name='Other Game'}
)
$membership | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $dir 'membership.json')
$canonical | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'canonical.json')
'[]' | Set-Content (Join-Path $dir 'unrated.json')
@(
    [pscustomobject]@{rank=1;item='Vindication: Archive of the Ancients'},
    [pscustomobject]@{rank=2;item='Other Game'}
) | Export-Csv (Join-Path $pubOut 'tier-S-ranking.csv') -NoTypeInformation

& (Join-Path $PSScriptRoot '../external-ordering/Normalize-BggExternalRankingData.ps1') `
    -MembershipPath (Join-Path $dir 'membership.json') `
    -CanonicalPath (Join-Path $dir 'canonical.json') `
    -UnratedRankedPath (Join-Path $dir 'unrated.json') `
    -TierExportDir $tierOut `
    -RankingExportDir $rankingOut `
    -TierImportPath (Join-Path $dir 'missing-tier-import.csv') `
    -RankingImportDir (Join-Path $dir 'missing-ranking-import') `
    -PubMeepleInputDir $pubIn `
    -PubMeepleOutputDir $pubOut `
    -PendingTierMovesPath (Join-Path $dir 'pending.json') `
    -NormalizedRankingImportPath (Join-Path $dir 'ordering.json') | Out-Null

$names = @(Get-Content (Join-Path $pubIn 'tier-S-ranking.txt'))
if ($names.Count -ne 2 -or $names[0] -ne 'Vindication' -or $names[1] -ne 'Other Game') {
    throw "Equivalent title import did not preserve the existing order: $($names -join ', ')"
}

Write-Host 'Ranking: equivalent edition titles preserve imported PubMeeple order.'
