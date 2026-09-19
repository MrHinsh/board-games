[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$systems = Join-Path $PSScriptRoot '../systems'
# Preserve rank/report -> tiers/rebalance. Use local data; never pull or push BGG.
$rank = & "$systems/ranking/stackrank/Export-BggStackRank.ps1"
$sheet = & "$systems/tiers/rating-sheet/New-BggRatingUploadSheet.ps1"
$report = & "$systems/ranking/top-report/Export-BggTop10.ps1" -CanonicalPath './data/working/canonical/games.json'
$tiers = & "$systems/tiers/membership/run.ps1"
$ordering = & "$systems/ranking/external-ordering/run.ps1" -PubMeepleInputDir './data/publish/pubmeeple/in'
$moves = & "$systems/tiers/moves/run.ps1"
$rebalance = & "$systems/ranking/rebalance/run.ps1" -ImportPath './data/working/ranking/external-ordering.json'
[pscustomobject]@{
    RankSet = $rank
    PublishQueue = $sheet
    Report = $report
    TierMap = $tiers
    Normalize = $ordering
    TierMove = $moves
    RankRebalance = $rebalance
}
