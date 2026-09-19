<#
.SYNOPSIS
    Score resolved nominations against the operator's own ratings.

.DESCRIPTION
    PROVISIONAL MODEL - see .agents/context/purchase-prediction.md. The scoring
    approach here has not been agreed as the house algorithm; it is a first cut
    and is designed to be replaced. Every run refits from canonical and prints
    its own fit statistics so the output can be argued with rather than trusted.

    Order of preference for a nomination's score:
      1. the operator's actual rating, when the game is already rated
      2. otherwise a predicted rating from the fitted model

    Model:
      pred = b0 + b1*complexity + b2*bgg_rating + b3*scifi + designer_adjustment

    The designer adjustment is the mean residual of that designer's already-rated
    games. Designers are read from a cached index built by fetching bgg-details
    for every rated game in canonical (canonical itself carries no designer).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResolvedPath,

    [Parameter(Mandatory = $true)]
    [string]$OutPath,

    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$DesignerIndexPath = '.\data\working\nominations\designer-index.json',
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [int]$DesignerIndexMaxAgeDays = 30,
    [ValidateSet('compact', 'full')]
    [string]$FeatureSet = 'compact',
    [switch]$RefreshDesignerIndex
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/prediction/club-nominations/Score-Nominations.ps1') @PSBoundParameters
