[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [string]$Endpoint = 'http://localhost:8080/mcp',
    [string]$ApiKey,
    [string]$Cookie,
    [switch]$IncludeExpansions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fetchScript = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-fetch\scripts\run.ps1'
$reconcileScript = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-reconcile\scripts\run.ps1'
$rankSetScript = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-rank-set\scripts\Export-BggStackRank.ps1'
$publishQueueScript = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-publish-queue\scripts\New-BggRatingUploadSheet.ps1'
$reportScript = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-report\scripts\Export-BggTop10.ps1'
$tierMapScript = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-tier-map\scripts\run.ps1'
$normalizeScript = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-normalize\scripts\run.ps1'
$tierMoveScript = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-tier-move\scripts\run.ps1'
$rankRebalanceScript = Join-Path $PSScriptRoot '..\..\mrhinsh-bg-rank-rebalance\scripts\run.ps1'

foreach ($script in @(
    $fetchScript,
    $reconcileScript,
    $rankSetScript,
    $publishQueueScript,
    $reportScript,
    $tierMapScript,
    $normalizeScript,
    $tierMoveScript,
    $rankRebalanceScript
)) {
    if (-not (Test-Path $script)) {
        throw "Missing script: $script"
    }
}

$snapshot = & $fetchScript -Username $Username -Endpoint $Endpoint -ApiKey $ApiKey -Cookie $Cookie -IncludeExpansions:$IncludeExpansions
$reconcileResult = & $reconcileScript -SnapshotPath $snapshot
$rankSetResult = & $rankSetScript
$publishQueueResult = & $publishQueueScript
$reportResult = & $reportScript -Username $Username -Endpoint $Endpoint -ApiKey $ApiKey -Cookie $Cookie -IncludeExpansions:$IncludeExpansions
$tierMapResult = & $tierMapScript
$normalizeResult = & $normalizeScript
$tierMoveResult = & $tierMoveScript
$rankRebalanceResult = & $rankRebalanceScript -ImportPath '.\data\working\ranking\external-ordering.json'

[pscustomobject]@{
    Username = $Username
    Endpoint = $Endpoint
    IncludeExpansions = [bool]$IncludeExpansions
    SnapshotPath = $snapshot
    Reconcile = $reconcileResult
    RankSet = $rankSetResult
    PublishQueue = $publishQueueResult
    Report = $reportResult
    TierMap = $tierMapResult
    Normalize = $normalizeResult
    TierMove = $tierMoveResult
    RankRebalance = $rankRebalanceResult
}