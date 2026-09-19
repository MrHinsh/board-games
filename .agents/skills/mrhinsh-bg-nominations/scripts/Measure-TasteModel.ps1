<#
.SYNOPSIS
    Compare taste model v2 against v1 and the trivial baselines, out-of-sample.

.DESCRIPTION
    Every figure here is k-fold cross-validated. A model is only worth using if
    it beats "predict the average" and "rescale the BGG rating" by a margin that
    matters. Run this after any change to the model or a material change to the
    collection.
#>
[CmdletBinding()]
param(
    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$DesignerIndexPath = '.\data\working\nominations\designer-index.json',
    [int]$MinFeatureCount = 15,
    [int]$Folds = 5,
    [double[]]$Lambdas = @(1, 3, 10, 30, 100, 300)
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/prediction/club-nominations/Measure-TasteModel.ps1') @PSBoundParameters
