<#
.SYNOPSIS
    Bootstrap the ranking to measure how stable it actually is.

.DESCRIPTION
    CV RMSE describes the average error of a predicted *rating*. It is the wrong
    statistic for judging a *ranking*, and using it as a resolution threshold is
    doubly wrong: errors between similar games are correlated, so the difference
    between two predictions is far better determined than either level.

    This resamples the training set with replacement, refits, re-scores every
    nomination, and reports what actually matters:

      - how often each game lands in the operator's top 3
      - the spread of its rank across resamples
      - pairwise P(A above B) for the contenders

    Games with an actual rating are held fixed - there is nothing to resample.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RankedPath,

    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$DesignerIndexPath = '.\data\working\nominations\designer-index.json',
    [int]$Bootstraps = 300,
    [double]$Lambda = 30,
    [double]$ShrinkK = 3.0,
    [int]$TopN = 3,
    [int]$Seed = 20260909,
    [string]$OutPath
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/prediction/club-nominations/Measure-RankStability.ps1') @PSBoundParameters
