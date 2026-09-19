param([string]$FixtureRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../support/BggTierHelpers.ps1')
if ((Convert-TierRankToBggRating -Tier S -SourceBucket 10 -RankInTier 1 -TierCount 29) -ne 9.999) { throw 'S-tier upper endpoint regressed.' }
if ((Convert-TierRankToBggRating -Tier S -SourceBucket 10 -RankInTier 29 -TierCount 29) -ne 9) { throw 'S-tier lower endpoint regressed.' }
if ((Convert-TierRankToBggRating -Tier F -SourceBucket 3 -RankInTier 1 -TierCount 1) -ne 4.999) { throw 'Merged F singleton regressed.' }
$caught=$false
try { Convert-TierRankToBggRating -Tier X -SourceBucket 0 -RankInTier 1 -TierCount 1 | Out-Null } catch { $caught=$true }
if (-not $caught) { throw 'Exit tier should reject conversion.' }
$dir=Join-Path $FixtureRoot 'ranking'
New-Item -ItemType Directory -Path $dir | Out-Null
$games=@(
    @{bgg_id=1;name='Owned';year_published=2020;rating=8;num_plays=2;collection=$true},
    @{bgg_id=2;name='Not owned';year_published=2020;rating=10;num_plays=5;collection=$false},
    @{bgg_id=3;name='Unrated';year_published=2020;rating=0;num_plays=1;collection=$true}
)
$games | ConvertTo-Json | Set-Content "$dir/games.json"
& (Join-Path $PSScriptRoot '../top-report/Export-BggTop10.ps1') -CanonicalPath "$dir/games.json" -OutDir "$dir/report" | Out-Null
$rows=@(Get-Content "$dir/report/top-10.json" -Raw | ConvertFrom-Json)
if ($rows.Count -ne 1 -or $rows[0].bgg_id -ne 1) { throw 'Local top report must contain only owned rated games.' }
Write-Host 'Ranking: decimal boundaries and local owned/rated reporting passed.'
