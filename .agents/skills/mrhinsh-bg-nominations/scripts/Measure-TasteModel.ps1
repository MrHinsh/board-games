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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\..\mrhinsh-bg-shared\scripts\BggTasteModel.ps1')

$canon = @(Get-Content -Path $CanonicalPath -Raw | ConvertFrom-Json)
$train = @($canon | Where-Object {
    [double]$_.rating -gt 0 -and [double]$_.complexity -gt 0 -and [double]$_.bgg_rating -gt 0
})

$designerById = @{}
if (Test-Path $DesignerIndexPath) {
    $cached = Get-Content -Path $DesignerIndexPath -Raw | ConvertFrom-Json
    foreach ($p in $cached.PSObject.Properties) { $designerById[[int]$p.Name] = @($p.Value) }
} else {
    Write-Warning "No designer index at $DesignerIndexPath; designer term will be empty."
}

Write-Host "Training rows: $($train.Count)"
Write-Host "Designer index: $($designerById.Count) games"
Write-Host ''

$base = Get-BggBaselineRmse -Games $train -Folds $Folds
Write-Host '=== baselines (cross-validated RMSE, lower is better) ==='
Write-Host ("  predict the mean       : {0}" -f [math]::Round($base.MeanOnlyRmse, 3))
Write-Host ("  BGG rating rescaled    : {0}" -f [math]::Round($base.BggOnlyRmse, 3))
Write-Host ''

$fitted = @{}
foreach ($fs in @('compact', 'full')) {
    Write-Host "Fitting '$fs'..."
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $m = New-BggTasteModel -Games $train -DesignerById $designerById -MinFeatureCount $MinFeatureCount -Folds $Folds -FeatureSet $fs
    $sw.Stop()
    $fitted[$fs] = $m
    Write-Host ("  {0,-8} features={1,-3} lambda={2,-6} CV RMSE={3}  (no designer {4})  [{5}s]" -f `
        $fs, $m.FeatureNames.Count, $m.Lambda, [math]::Round($m.CvRmse, 3), [math]::Round($m.CvRmseNoDesigner, 3), [math]::Round($sw.Elapsed.TotalSeconds, 1))
    $maxLambda = ($m.LambdaSweep | Measure-Object -Property Lambda -Maximum).Maximum
    if ($m.Lambda -eq $maxLambda) {
        Write-Warning "  '$fs': chosen lambda is the largest offered - sweep has not bottomed out."
    }
}

$model = $fitted['compact']

Write-Host ''
Write-Host '=== league table (cross-validated RMSE, lower is better) ==='
$table = @(
    [pscustomobject]@{ Model = 'predict the mean';            Rmse = $base.MeanOnlyRmse }
    [pscustomobject]@{ Model = 'BGG rating rescaled';         Rmse = $base.BggOnlyRmse }
    [pscustomobject]@{ Model = 'full, no designer';           Rmse = $fitted['full'].CvRmseNoDesigner }
    [pscustomobject]@{ Model = 'compact, no designer';        Rmse = $fitted['compact'].CvRmseNoDesigner }
    [pscustomobject]@{ Model = 'full + designer';             Rmse = $fitted['full'].CvRmse }
    [pscustomobject]@{ Model = 'compact + designer (SHIPPED)'; Rmse = $fitted['compact'].CvRmse }
)
$table | Sort-Object Rmse -Descending | ForEach-Object {
    Write-Host ("  {0,-30} {1}" -f $_.Model, [math]::Round($_.Rmse, 3))
}

$improvement = ($base.BggOnlyRmse - $model.CvRmse) / $base.BggOnlyRmse * 100
Write-Host ''
Write-Host ("=== shipped model vs BGG-rating baseline: {0}% {1} ===" -f [math]::Abs([math]::Round($improvement, 1)), $(if ($improvement -gt 0) { 'better' } else { 'WORSE' }))
if ($improvement -le 0) {
    Write-Host '  The model does not beat simply rescaling the BGG rating. Do not ship it.' -ForegroundColor Yellow
}
if ($fitted['full'].CvRmse -lt $fitted['compact'].CvRmse) {
    Write-Host "  'full' now beats 'compact' - switch Score-Nominations.ps1 to -FeatureSet full." -ForegroundColor Yellow
}

$model = $fitted['full']  # show the learned mechanic weights, which only 'full' has

Write-Host ''
Write-Host '=== strongest learned weights (standardised) ==='
$pairs = for ($i = 0; $i -lt $model.FeatureNames.Count; $i++) {
    [pscustomobject]@{ Feature = $model.FeatureNames[$i]; Weight = $model.Fit.Beta[$i] }
}
Write-Host '  -- likes --'
$pairs | Sort-Object Weight -Descending | Select-Object -First 12 |
    ForEach-Object { Write-Host ("    {0,-46} {1,6}" -f $_.Feature, [math]::Round($_.Weight, 3)) }
Write-Host '  -- dislikes --'
$pairs | Sort-Object Weight | Select-Object -First 12 |
    ForEach-Object { Write-Host ("    {0,-46} {1,6}" -f $_.Feature, [math]::Round($_.Weight, 3)) }

Write-Host ''
Write-Host '=== strongest designer adjustments (shrunk) ==='
$model.DesignerAdj.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 |
    ForEach-Object { Write-Host ("    {0,-34} {1,6}" -f $_.Key, [math]::Round($_.Value, 3)) }
$model.DesignerAdj.GetEnumerator() | Sort-Object Value | Select-Object -First 5 |
    ForEach-Object { Write-Host ("    {0,-34} {1,6}" -f $_.Key, [math]::Round($_.Value, 3)) }
