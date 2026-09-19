[CmdletBinding()]
param(
    [string]$MembershipPath = '.\data\working\ranking\tier-membership.json',
    [string]$QueuePath = '.\data\publish\queue\pending-tier-moves.json',
    [string]$ImportPath,
    [int]$GameId,
    [ValidateSet('S', 'A', 'B', 'C', 'D', 'F', 'U', 'X')]
    [string]$Tier,
    [int]$SourceBucket = -1,
    [string]$Notes = ''
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/tiers/moves/Apply-BggTierMoves.ps1') @PSBoundParameters
