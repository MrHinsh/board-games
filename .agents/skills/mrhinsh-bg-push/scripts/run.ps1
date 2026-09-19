[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$QueuePath = '.\data\publish\queue\pending-rating-updates.json',
    [string]$Username,
    [int]$Limit = 0
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/bgg-integration/push/run.ps1') @PSBoundParameters
