# Emit a compact status summary of the pipeline so agents/operators can brief
# without loading any large data file into context.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent

function Read-JsonSafe {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

$games = @(Read-JsonSafe (Join-Path $repoRoot 'data\working\canonical\games.json'))
$queue = @(Read-JsonSafe (Join-Path $repoRoot 'data\publish\queue\pending-rating-updates.json'))
$tierMoves = @(Read-JsonSafe (Join-Path $repoRoot 'data\publish\queue\pending-tier-moves.json'))

$rated = @($games | Where-Object { $_.rating -gt 0 })
$unrated = @($games | Where-Object { $_.rating -eq 0 })
$unratedPlayed = @($unrated | Where-Object { $_.num_plays -gt 0 })

$queueWithDelta = @($queue | Where-Object { [Math]::Abs([decimal]$_.delta) -gt 0 })
$largeDeltas = @($queueWithDelta | Where-Object { [Math]::Abs([decimal]$_.delta) -gt 2 })

$snapshotDir = Join-Path $repoRoot 'data\raw\bgg\collection'
$lastSnapshot = $null
if (Test-Path $snapshotDir) {
    $snapshots = @(Get-ChildItem $snapshotDir -Filter '*.json' | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}' } |
        Sort-Object Name -Descending)
    if ($snapshots.Count -gt 0) { $lastSnapshot = $snapshots[0].Name }
}

$checkpointDir = Join-Path $repoRoot 'data\state\checkpoints'
$lastCheckpoint = $null
if (Test-Path $checkpointDir) {
    $checkpoints = @(Get-ChildItem $checkpointDir -Directory | Sort-Object Name -Descending)
    if ($checkpoints.Count -gt 0) { $lastCheckpoint = $checkpoints[0].Name }
}

[pscustomobject]@{
    canonical_games = $games.Count
    rated = $rated.Count
    unrated = $unrated.Count
    unrated_with_plays = $unratedPlayed.Count
    queue_total = $queue.Count
    queue_with_change = $queueWithDelta.Count
    queue_large_deltas = @($largeDeltas | Select-Object bgg_id, name, tier, current_rating, target_rating, delta)
    pending_tier_moves = $tierMoves.Count
    last_snapshot = $lastSnapshot
    last_checkpoint = $lastCheckpoint
    top_unrated_by_plays = @($unratedPlayed | Sort-Object num_plays -Descending |
        Select-Object -First 10 bgg_id, name, num_plays)
} | ConvertTo-Json -Depth 5
