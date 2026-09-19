[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$QueuePath = '.\data\publish\queue\pending-rating-updates.json',
    [string]$Username,
    [int]$Limit = 0,

    # Ratings jumps larger than this require -AllowLargeDelta (guards against a bad rebalance)
    [decimal]$MaxDelta = 2.0,
    [switch]$AllowLargeDelta
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/bgg-integration/ratings/Sync-BggRatingQueue.ps1') @PSBoundParameters
