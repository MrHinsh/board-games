<#
.SYNOPSIS
    Taste model v2 - learns per-mechanic and per-category weights from the
    operator's own ratings.

.DESCRIPTION
    v1 was a 3-feature regression in which the BGG community rating carried the
    largest coefficient, so it mostly predicted consensus rather than taste. v2
    learns what the operator actually likes from the mechanics and categories
    already present in canonical, and demotes bgg_rating to one input among many.

    - Ridge regression (L2). Feature count is close to the row count, so an
      unpenalised fit would overfit badly.
    - Features standardised before fitting; the intercept is not penalised.
    - Designer effect is a shrunk mean residual, n/(n+K), so a designer with two
      games cannot swing a prediction the way a hard n>=3 cliff allowed.
    - Lambda chosen by k-fold cross-validation, and every reported accuracy
      figure is out-of-sample. In-sample R^2 is not reported: it flatters.

    Dot-source this file, then call New-BggTasteModel / Get-BggTastePrediction.
#>

Set-StrictMode -Version Latest

function Resolve-LinearSystem {
    param([double[,]]$A, [double[]]$B)

    $k = $B.Count
    $M = New-Object 'double[,]' $k, ($k + 1)
    for ($r = 0; $r -lt $k; $r++) {
        for ($c = 0; $c -lt $k; $c++) { $M[$r, $c] = $A[$r, $c] }
        $M[$r, $k] = $B[$r]
    }

    for ($c = 0; $c -lt $k; $c++) {
        $piv = $c
        for ($r = $c + 1; $r -lt $k; $r++) {
            if ([math]::Abs($M[$r, $c]) -gt [math]::Abs($M[$piv, $c])) { $piv = $r }
        }
        if ([math]::Abs($M[$piv, $c]) -lt 1e-12) { throw 'Singular system; increase lambda.' }
        if ($piv -ne $c) {
            for ($q = 0; $q -le $k; $q++) { $t = $M[$c, $q]; $M[$c, $q] = $M[$piv, $q]; $M[$piv, $q] = $t }
        }
        for ($r = 0; $r -lt $k; $r++) {
            if ($r -ne $c) {
                $f = $M[$r, $c] / $M[$c, $c]
                for ($q = $c; $q -le $k; $q++) { $M[$r, $q] -= $f * $M[$c, $q] }
            }
        }
    }

    $x = New-Object 'double[]' $k
    for ($c = 0; $c -lt $k; $c++) { $x[$c] = $M[$c, $k] / $M[$c, $c] }
    return $x
}

function Get-BggFeatureNames {
    param(
        [object[]]$Games,
        [int]$MinFeatureCount = 15,
        [ValidateSet('compact', 'full')]
        [string]$FeatureSet = 'compact'
    )

    # 'compact' won on cross-validation. The 78-feature 'full' set scored WORSE
    # than these three once both carried the designer term - see
    # .agents/context/purchase-prediction.md. Kept so the comparison can be
    # re-run as the collection grows.
    if ($FeatureSet -eq 'compact') {
        return @('complexity', 'bgg_rating', 'scifi')
    }

    $mech = @{}; $cat = @{}
    foreach ($g in $Games) {
        foreach ($m in @($g.mechanics)) { if ($m) { $mech[$m] = 1 + $(if ($mech.ContainsKey($m)) { $mech[$m] } else { 0 }) } }
        foreach ($c in @($g.categories)) { if ($c) { $cat[$c] = 1 + $(if ($cat.ContainsKey($c)) { $cat[$c] } else { 0 }) } }
    }

    $names = [System.Collections.Generic.List[string]]::new()
    $names.Add('complexity')
    $names.Add('bgg_rating')
    foreach ($m in ($mech.Keys | Sort-Object)) { if ($mech[$m] -ge $MinFeatureCount) { $names.Add("mech:$m") } }
    foreach ($c in ($cat.Keys | Sort-Object)) { if ($cat[$c] -ge $MinFeatureCount) { $names.Add("cat:$c") } }
    return $names.ToArray()
}

function Get-BggFeatureVector {
    param($Game, [string[]]$FeatureNames)

    $mset = @{}; foreach ($m in @($Game.mechanics)) { if ($m) { $mset[$m] = $true } }
    $cset = @{}; foreach ($c in @($Game.categories)) { if ($c) { $cset[$c] = $true } }

    $v = New-Object 'double[]' $FeatureNames.Count
    for ($i = 0; $i -lt $FeatureNames.Count; $i++) {
        $n = $FeatureNames[$i]
        if ($n -eq 'complexity')      { $v[$i] = [double]$Game.complexity }
        elseif ($n -eq 'bgg_rating')  { $v[$i] = [double]$Game.bgg_rating }
        elseif ($n -eq 'scifi')       { $v[$i] = $(if ((@($Game.categories) -join ' ') -match 'Science Fiction|Space Exploration') { 1.0 } else { 0.0 }) }
        elseif ($n.StartsWith('mech:')) { $v[$i] = $(if ($mset.ContainsKey($n.Substring(5))) { 1.0 } else { 0.0 }) }
        elseif ($n.StartsWith('cat:'))  { $v[$i] = $(if ($cset.ContainsKey($n.Substring(4))) { 1.0 } else { 0.0 }) }
    }
    return $v
}

function Get-RidgeFit {
    param([double[][]]$X, [double[]]$Y, [double]$Lambda)

    $n = $Y.Count
    $p = $X[0].Count

    $mean = New-Object 'double[]' $p
    $sd = New-Object 'double[]' $p
    for ($j = 0; $j -lt $p; $j++) {
        $s = 0.0
        for ($i = 0; $i -lt $n; $i++) { $s += $X[$i][$j] }
        $mean[$j] = $s / $n
        $v = 0.0
        for ($i = 0; $i -lt $n; $i++) { $d = $X[$i][$j] - $mean[$j]; $v += $d * $d }
        $sdv = [math]::Sqrt($v / $n)
        $sd[$j] = $(if ($sdv -lt 1e-9) { 1.0 } else { $sdv })
    }

    $yMean = ($Y | Measure-Object -Average).Average

    # Z'Z + lambda*I  and  Z'yc, on standardised, centred data
    $A = New-Object 'double[,]' $p, $p
    $B = New-Object 'double[]' $p
    $Z = New-Object 'double[][]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $row = New-Object 'double[]' $p
        for ($j = 0; $j -lt $p; $j++) { $row[$j] = ($X[$i][$j] - $mean[$j]) / $sd[$j] }
        $Z[$i] = $row
    }
    for ($j = 0; $j -lt $p; $j++) {
        for ($k = $j; $k -lt $p; $k++) {
            $s = 0.0
            for ($i = 0; $i -lt $n; $i++) { $s += $Z[$i][$j] * $Z[$i][$k] }
            $A[$j, $k] = $s
            $A[$k, $j] = $s
        }
        $A[$j, $j] += $Lambda
        $s = 0.0
        for ($i = 0; $i -lt $n; $i++) { $s += $Z[$i][$j] * ($Y[$i] - $yMean) }
        $B[$j] = $s
    }

    $beta = Resolve-LinearSystem -A $A -B $B
    return [pscustomobject]@{ Beta = $beta; Mean = $mean; Sd = $sd; YMean = $yMean; Lambda = $Lambda }
}

function Get-RidgePrediction {
    param($Fit, [double[]]$XRow)
    $p = $XRow.Count
    $acc = $Fit.YMean
    for ($j = 0; $j -lt $p; $j++) {
        $acc += $Fit.Beta[$j] * (($XRow[$j] - $Fit.Mean[$j]) / $Fit.Sd[$j])
    }
    return $acc
}

function Get-ShrunkDesignerAdjustment {
    param(
        [hashtable]$DesignerById,
        [object[]]$Games,
        [double[]]$Residuals,
        [double]$ShrinkK = 5.0
    )

    $acc = @{}
    for ($i = 0; $i -lt $Games.Count; $i++) {
        $id = [int]$Games[$i].bgg_id
        if (-not $DesignerById.ContainsKey($id)) { continue }
        foreach ($d in $DesignerById[$id]) {
            if (-not $acc.ContainsKey($d)) { $acc[$d] = [System.Collections.Generic.List[double]]::new() }
            $acc[$d].Add($Residuals[$i])
        }
    }

    $adj = @{}
    foreach ($d in $acc.Keys) {
        $lst = $acc[$d]
        $m = ($lst | Measure-Object -Average).Average
        # shrink toward zero by sample size: no cliff, two games barely move it
        $adj[$d] = ($lst.Count / ($lst.Count + $ShrinkK)) * $m
    }
    return $adj
}

function New-BggTasteModel {
    <#
    .SYNOPSIS
        Fit the taste model, choosing lambda by k-fold cross-validation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Games,
        [hashtable]$DesignerById = @{},
        [int]$MinFeatureCount = 15,
        [ValidateSet('compact', 'full')]
        [string]$FeatureSet = 'compact',
        [double[]]$Lambdas,
        [int]$Folds = 5,
        [double]$ShrinkK = 3.0,
        [int]$Seed = 20260909
    )

    if (-not $PSBoundParameters.ContainsKey('Lambdas')) {
        # compact has 3 features and wants almost no penalty; full has ~78
        $Lambdas = $(if ($FeatureSet -eq 'compact') { @(0.1, 1, 3, 10, 30, 100, 300) } else { @(10, 30, 100, 300, 1000, 3000) })
    }

    $featureNames = Get-BggFeatureNames -Games $Games -MinFeatureCount $MinFeatureCount -FeatureSet $FeatureSet
    $n = $Games.Count

    $X = New-Object 'double[][]' $n
    $Y = New-Object 'double[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $X[$i] = Get-BggFeatureVector -Game $Games[$i] -FeatureNames $featureNames
        $Y[$i] = [double]$Games[$i].rating
    }

    $rand = [System.Random]::new($Seed)
    $foldOf = New-Object 'int[]' $n
    $order = @(0..($n - 1) | Sort-Object { $rand.Next() })
    for ($k = 0; $k -lt $n; $k++) { $foldOf[$order[$k]] = $k % $Folds }

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($lambda in $Lambdas) {
        $se = 0.0; $seNoDesigner = 0.0
        for ($f = 0; $f -lt $Folds; $f++) {
            $trIdx = @(0..($n - 1) | Where-Object { $foldOf[$_] -ne $f })
            $teIdx = @(0..($n - 1) | Where-Object { $foldOf[$_] -eq $f })

            $Xtr = New-Object 'double[][]' $trIdx.Count
            $Ytr = New-Object 'double[]' $trIdx.Count
            for ($i = 0; $i -lt $trIdx.Count; $i++) { $Xtr[$i] = $X[$trIdx[$i]]; $Ytr[$i] = $Y[$trIdx[$i]] }

            $fit = Get-RidgeFit -X $Xtr -Y $Ytr -Lambda $lambda

            # designer adjustment learned on the training fold only
            $trGames = @($trIdx | ForEach-Object { $Games[$_] })
            $trResid = New-Object 'double[]' $trIdx.Count
            for ($i = 0; $i -lt $trIdx.Count; $i++) {
                $trResid[$i] = $Ytr[$i] - (Get-RidgePrediction -Fit $fit -XRow $Xtr[$i])
            }
            $dAdj = Get-ShrunkDesignerAdjustment -DesignerById $DesignerById -Games $trGames -Residuals $trResid -ShrinkK $ShrinkK

            foreach ($t in $teIdx) {
                $base = Get-RidgePrediction -Fit $fit -XRow $X[$t]
                $adj = 0.0
                $id = [int]$Games[$t].bgg_id
                if ($DesignerById.ContainsKey($id)) {
                    $hits = @($DesignerById[$id] | Where-Object { $dAdj.ContainsKey($_) })
                    if ($hits.Count -gt 0) { $adj = (@($hits | ForEach-Object { $dAdj[$_] }) | Measure-Object -Average).Average }
                }
                $se += [math]::Pow($Y[$t] - ($base + $adj), 2)
                $seNoDesigner += [math]::Pow($Y[$t] - $base, 2)
            }
        }
        $results.Add([pscustomobject]@{
            Lambda = $lambda
            CvRmse = [math]::Sqrt($se / $n)
            CvRmseNoDesigner = [math]::Sqrt($seNoDesigner / $n)
        })
    }

    $best = $results | Sort-Object CvRmse | Select-Object -First 1

    # final fit on everything, at the chosen lambda
    $fit = Get-RidgeFit -X $X -Y $Y -Lambda $best.Lambda
    $resid = New-Object 'double[]' $n
    for ($i = 0; $i -lt $n; $i++) { $resid[$i] = $Y[$i] - (Get-RidgePrediction -Fit $fit -XRow $X[$i]) }
    $designerAdj = Get-ShrunkDesignerAdjustment -DesignerById $DesignerById -Games $Games -Residuals $resid -ShrinkK $ShrinkK

    return [pscustomobject]@{
        FeatureSet   = $FeatureSet
        FeatureNames = $featureNames
        Fit          = $fit
        DesignerAdj  = $designerAdj
        DesignerById = $DesignerById
        Lambda       = $best.Lambda
        CvRmse       = $best.CvRmse
        CvRmseNoDesigner = $best.CvRmseNoDesigner
        LambdaSweep  = $results
        N            = $n
        ShrinkK      = $ShrinkK
    }
}

function Get-BggTastePrediction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Model,
        [Parameter(Mandatory = $true)]$Game,
        [string[]]$Designers = @()
    )

    $x = Get-BggFeatureVector -Game $Game -FeatureNames $Model.FeatureNames
    $base = Get-RidgePrediction -Fit $Model.Fit -XRow $x

    $hits = @($Designers | Where-Object { $Model.DesignerAdj.ContainsKey($_) })
    $adj = 0.0
    if ($hits.Count -gt 0) { $adj = (@($hits | ForEach-Object { $Model.DesignerAdj[$_] }) | Measure-Object -Average).Average }

    return [pscustomobject]@{
        Base = $base
        DesignerAdjustment = $adj
        DesignerHits = $hits
        Prediction = $base + $adj
    }
}

function Get-BggBaselineRmse {
    <#
    .SYNOPSIS
        Out-of-sample RMSE for the trivial baselines the model must beat.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Games,
        [int]$Folds = 5,
        [int]$Seed = 20260909
    )

    $n = $Games.Count
    $Y = New-Object 'double[]' $n
    $R = New-Object 'double[]' $n
    for ($i = 0; $i -lt $n; $i++) { $Y[$i] = [double]$Games[$i].rating; $R[$i] = [double]$Games[$i].bgg_rating }

    $rand = [System.Random]::new($Seed)
    $foldOf = New-Object 'int[]' $n
    $order = @(0..($n - 1) | Sort-Object { $rand.Next() })
    for ($k = 0; $k -lt $n; $k++) { $foldOf[$order[$k]] = $k % $Folds }

    $seMean = 0.0; $seBgg = 0.0
    for ($f = 0; $f -lt $Folds; $f++) {
        $trIdx = @(0..($n - 1) | Where-Object { $foldOf[$_] -ne $f })
        $teIdx = @(0..($n - 1) | Where-Object { $foldOf[$_] -eq $f })

        $ym = (@($trIdx | ForEach-Object { $Y[$_] }) | Measure-Object -Average).Average

        # simple regression of own rating on bgg rating, fitted on the fold
        $rm = (@($trIdx | ForEach-Object { $R[$_] }) | Measure-Object -Average).Average
        $num = 0.0; $den = 0.0
        foreach ($i in $trIdx) { $dr = $R[$i] - $rm; $num += $dr * ($Y[$i] - $ym); $den += $dr * $dr }
        $slope = $(if ($den -gt 1e-9) { $num / $den } else { 0.0 })

        foreach ($t in $teIdx) {
            $seMean += [math]::Pow($Y[$t] - $ym, 2)
            $seBgg  += [math]::Pow($Y[$t] - ($ym + $slope * ($R[$t] - $rm)), 2)
        }
    }

    return [pscustomobject]@{
        MeanOnlyRmse = [math]::Sqrt($seMean / $n)
        BggOnlyRmse  = [math]::Sqrt($seBgg / $n)
    }
}
