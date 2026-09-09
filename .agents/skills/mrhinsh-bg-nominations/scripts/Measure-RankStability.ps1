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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\..\mrhinsh-bg-shared\scripts\BggTasteModel.ps1')

$canon = @(Get-Content -Path $CanonicalPath -Raw | ConvertFrom-Json)
$train = @($canon | Where-Object {
    [double]$_.rating -gt 0 -and [double]$_.complexity -gt 0 -and [double]$_.bgg_rating -gt 0
})

$designerById = @{}
if (Test-Path $DesignerIndexPath) {
    $c = Get-Content -Path $DesignerIndexPath -Raw | ConvertFrom-Json
    foreach ($p in $c.PSObject.Properties) { $designerById[[int]$p.Name] = @($p.Value) }
}

$ranked = @(Import-Csv -Path $RankedPath)
$featureNames = @('complexity', 'bgg_rating', 'scifi')

# training design matrix, built once
$nTr = $train.Count
$Xtr = New-Object 'double[][]' $nTr
$Ytr = New-Object 'double[]' $nTr
for ($i = 0; $i -lt $nTr; $i++) {
    $Xtr[$i] = Get-BggFeatureVector -Game $train[$i] -FeatureNames $featureNames
    $Ytr[$i] = [double]$train[$i].rating
}

# nomination feature rows; a game with an actual rating is fixed, not predicted
$nom = foreach ($r in $ranked) {
    $actual = $null
    if ($r.actual_rating -and $r.actual_rating -ne '') { $actual = [double]$r.actual_rating }
    [pscustomobject]@{
        Game      = $r.game
        Host      = $r.host
        Actual    = $actual
        Designers = @((([string]$r.designer_hits) -split '\s*/\s*') | Where-Object { $_ })
        X         = [double[]]@([double]$r.complexity, [double]$r.bgg_rating, [double]$r.scifi)
    }
}
$nom = @($nom)

$rand = [System.Random]::new($Seed)
$rankCounts = @{}
$topCounts = @{}
$rankLists = @{}
foreach ($g in $nom) { $rankLists[$g.Game] = [System.Collections.Generic.List[int]]::new(); $topCounts[$g.Game] = 0 }

for ($b = 0; $b -lt $Bootstraps; $b++) {
    # resample training rows with replacement
    $idx = New-Object 'int[]' $nTr
    for ($i = 0; $i -lt $nTr; $i++) { $idx[$i] = $rand.Next($nTr) }

    $Xb = New-Object 'double[][]' $nTr
    $Yb = New-Object 'double[]' $nTr
    for ($i = 0; $i -lt $nTr; $i++) { $Xb[$i] = $Xtr[$idx[$i]]; $Yb[$i] = $Ytr[$idx[$i]] }

    $fit = Get-RidgeFit -X $Xb -Y $Yb -Lambda $Lambda

    $resid = New-Object 'double[]' $nTr
    $gamesB = New-Object 'object[]' $nTr
    for ($i = 0; $i -lt $nTr; $i++) {
        $resid[$i] = $Yb[$i] - (Get-RidgePrediction -Fit $fit -XRow $Xb[$i])
        $gamesB[$i] = $train[$idx[$i]]
    }
    $dAdj = Get-ShrunkDesignerAdjustment -DesignerById $designerById -Games $gamesB -Residuals $resid -ShrinkK $ShrinkK

    $scored = foreach ($g in $nom) {
        $s = 0.0
        if ($null -ne $g.Actual) {
            $s = $g.Actual
        } else {
            $s = Get-RidgePrediction -Fit $fit -XRow $g.X
            $hits = @($g.Designers | Where-Object { $dAdj.ContainsKey($_) })
            if ($hits.Count -gt 0) { $s += (@($hits | ForEach-Object { $dAdj[$_] }) | Measure-Object -Average).Average }
        }
        [pscustomobject]@{ Game = $g.Game; Score = $s }
    }

    $ordered = @($scored | Sort-Object -Property Score -Descending)
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $rankLists[$ordered[$i].Game].Add($i + 1)
        if ($i -lt $TopN) { $topCounts[$ordered[$i].Game]++ }
    }
}

$summary = foreach ($g in $nom) {
    $l = $rankLists[$g.Game]
    $sorted = @($l | Sort-Object)
    [pscustomobject]@{
        Game      = $g.Game
        Host      = $g.Host
        Basis     = $(if ($null -ne $g.Actual) { 'RATED' } else { 'pred' })
        MedRank   = $sorted[[int][math]::Floor($sorted.Count * 0.5)]
        P05       = $sorted[[int][math]::Floor($sorted.Count * 0.05)]
        P95       = $sorted[[int][math]::Min($sorted.Count - 1, [math]::Floor($sorted.Count * 0.95))]
        PctTopN   = [math]::Round(100.0 * $topCounts[$g.Game] / $Bootstraps, 1)
    }
}
$summary = @($summary | Sort-Object MedRank, @{ Expression = 'PctTopN'; Descending = $true })

Write-Host ("Bootstraps: {0}   training rows: {1}   lambda: {2}" -f $Bootstraps, $nTr, $Lambda)
Write-Host ''
Write-Host ("=== rank stability (rank 1 = best; P(top {0}) across resamples) ===" -f $TopN)
$summary | Select-Object -First 15 | Format-Table -AutoSize Game, Host, Basis, MedRank, P05, P95, PctTopN

if ($OutPath) {
    $dir = Split-Path -Parent $OutPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $summary | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8
    Write-Host "Wrote $OutPath"
}

# pairwise dominance among the contenders
$top = @($summary | Select-Object -First 6)
Write-Host ''
Write-Host '=== P(row scores above column), across resamples ==='
foreach ($a in $top) {
    $line = "  {0,-28}" -f $a.Game.Substring(0, [Math]::Min(28, $a.Game.Length))
    foreach ($b in $top) {
        if ($a.Game -eq $b.Game) { $line += '    -  '; continue }
        $la = $rankLists[$a.Game]; $lb = $rankLists[$b.Game]
        $wins = 0
        for ($i = 0; $i -lt $la.Count; $i++) { if ($la[$i] -lt $lb[$i]) { $wins++ } }
        $line += "{0,6:P0}" -f ($wins / $la.Count)
    }
    Write-Host $line
}
Write-Host ('  columns, in order: ' + (($top | ForEach-Object { $_.Game.Split(':')[0] }) -join ' | '))
