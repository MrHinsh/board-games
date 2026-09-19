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
    games. Designers are read from a cached index covering every played game
    and every rated training game (canonical itself carries no designer).
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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../../bgg-integration/provider/Invoke-BggMcp.ps1')
. (Join-Path $PSScriptRoot '../model/BggTasteModel.ps1')
. (Join-Path $PSScriptRoot 'Update-DesignerIndex.ps1')

$sciFiPattern = 'Science Fiction|Space Exploration'

function Get-SciFiFlag {
    param($Categories)
    $c = @($Categories) -join ' '
    if ($c -match $sciFiPattern) { return 1.0 }
    return 0.0
}

function Get-OlsCoefficients {
    param([double[][]]$X, [double[]]$Y)

    $k = $X[0].Count
    $n = $Y.Count
    $A = New-Object 'double[,]' $k, ($k + 1)
    for ($p = 0; $p -lt $k; $p++) {
        for ($q = 0; $q -lt $k; $q++) {
            $s = 0.0
            for ($i = 0; $i -lt $n; $i++) { $s += $X[$i][$p] * $X[$i][$q] }
            $A[$p, $q] = $s
        }
        $s = 0.0
        for ($i = 0; $i -lt $n; $i++) { $s += $X[$i][$p] * $Y[$i] }
        $A[$p, $k] = $s
    }

    for ($c = 0; $c -lt $k; $c++) {
        $piv = $c
        for ($r = $c + 1; $r -lt $k; $r++) {
            if ([math]::Abs($A[$r, $c]) -gt [math]::Abs($A[$piv, $c])) { $piv = $r }
        }
        if ([math]::Abs($A[$piv, $c]) -lt 1e-12) { throw 'Design matrix is singular; cannot fit model.' }
        if ($piv -ne $c) {
            for ($q = 0; $q -le $k; $q++) { $t = $A[$c, $q]; $A[$c, $q] = $A[$piv, $q]; $A[$piv, $q] = $t }
        }
        for ($r = 0; $r -lt $k; $r++) {
            if ($r -ne $c) {
                $f = $A[$r, $c] / $A[$c, $c]
                for ($q = $c; $q -le $k; $q++) { $A[$r, $q] -= $f * $A[$c, $q] }
            }
        }
    }

    $coef = New-Object 'double[]' $k
    # divide through by the pivot - omitting this silently produces garbage
    for ($c = 0; $c -lt $k; $c++) { $coef[$c] = $A[$c, $k] / $A[$c, $c] }
    return $coef
}

# ---------------------------------------------------------------- canonical
if (-not (Test-Path $CanonicalPath)) { throw "Canonical file not found: $CanonicalPath" }
$canon = @(Get-Content -Path $CanonicalPath -Raw | ConvertFrom-Json)
$canonById = @{}
foreach ($c in $canon) { $canonById[[int]$c.bgg_id] = $c }

$train = @($canon | Where-Object {
    [double]$_.rating -gt 0 -and [double]$_.complexity -gt 0 -and [double]$_.bgg_rating -gt 0
})
if ($train.Count -lt 50) { throw "Only $($train.Count) usable training rows; refusing to fit." }

# ------------------------------------------------------- designer index cache
$designerById = Update-BggDesignerIndex -Games $canon -TrainingGames $train `
    -Path $DesignerIndexPath -Endpoint $Endpoint -MaxAgeDays $DesignerIndexMaxAgeDays `
    -Refresh:$RefreshDesignerIndex

# ------------------------------------------------------------------ fit model
$model = New-BggTasteModel -Games $train -DesignerById $designerById -FeatureSet $FeatureSet -Folds 5

Write-Host ''
Write-Host '=== fitted model (refit this run) ==='
Write-Host ("  feature set   = {0} ({1} features)" -f $model.FeatureSet, $model.FeatureNames.Count)
Write-Host ("  n             = {0}" -f $model.N)
Write-Host ("  lambda        = {0}" -f $model.Lambda)
Write-Host ("  CV RMSE       = {0}  (out-of-sample, 5-fold)" -f [math]::Round($model.CvRmse, 3))
Write-Host ("  without designer term: {0}" -f [math]::Round($model.CvRmseNoDesigner, 3))
Write-Host ("  designers with an adjustment: {0}" -f $model.DesignerAdj.Count)
Write-Host ("  NOTE: gaps smaller than ~{0} rating points are noise." -f [math]::Round($model.CvRmse, 1))
Write-Host ''

# ------------------------------------------------------------------- score
$resolved = @(Import-Csv -Path $ResolvedPath)
$ids = @($resolved | Where-Object { $_.bgg_id } | ForEach-Object { [int]$_.bgg_id } | Sort-Object -Unique)
$details = @()
for ($i = 0; $i -lt $ids.Count; $i += 20) {
    $batch = $ids[$i..([Math]::Min($i + 19, $ids.Count - 1))]
    $batchResult = @(Invoke-BggMcpTool -ToolName 'bgg-details' -Arguments @{ ids = $batch } -Endpoint $Endpoint)
    $details += @($batchResult | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'id' })
    Start-Sleep -Seconds 2
}
$detById = @{}
foreach ($d in $details) { if (-not $detById.ContainsKey([int]$d.id)) { $detById[[int]$d.id] = $d } }

$rows = foreach ($r in $resolved) {
    if (-not $r.bgg_id) { continue }
    $id = [int]$r.bgg_id
    if (-not $detById.ContainsKey($id)) { Write-Warning "No details for $($r.game_raw) ($id)"; continue }
    $g = $detById[$id]

    $w = [double]$g.complexity
    $bgg = [double]$g.bgg_rating
    $sf = Get-SciFiFlag $g.categories

    $designers = @((([string]$g.designer) -split ',\s*') | Where-Object { $_ })
    $p = Get-BggTastePrediction -Model $model -Game $g -Designers $designers
    $adj = $p.DesignerAdjustment
    $hits = $p.DesignerHits
    $pred = $p.Prediction

    $actual = $null; $status = ''; $plays = 0
    $wantPlay = $false; $wantBuy = $false
    if ($canonById.ContainsKey($id)) {
        $c = $canonById[$id]
        $status = [string]$c.collection_status
        $plays = [int]$c.num_plays
        $wantPlay = [bool]$c.want_to_play
        $wantBuy = [bool]$c.want_to_buy
        if ([double]$c.rating -gt 0) { $actual = [double]$c.rating }
    }

    [pscustomobject]@{
        host          = $r.host
        slot          = [int]$r.slot
        game_raw      = $r.game_raw
        game          = $g.name
        bgg_id        = $id
        complexity    = [math]::Round($w, 2)
        bgg_rating    = [math]::Round($bgg, 2)
        num_ratings   = $g.num_ratings
        scifi         = [int]$sf
        designer_adj  = [math]::Round($adj, 2)
        designer_hits = ($hits -join ' / ')
        predicted     = [math]::Round($pred, 2)
        actual_rating = $actual
        score         = $(if ($null -ne $actual) { $actual } else { [math]::Round($pred, 2) })
        basis         = $(if ($null -ne $actual) { 'RATED' } else { 'predicted' })
        collection    = $status
        plays         = $plays
        want_to_play  = $wantPlay
        want_to_buy   = $wantBuy
        players       = $g.players
        play_time     = $g.play_time
        host_comment  = $r.PSObject.Properties['host_comment'] ? $r.host_comment : ''
    }
}

$sorted = @($rows | Sort-Object -Property @{ Expression = { [double]$_.score }; Descending = $true })
$outDir = Split-Path -Parent $OutPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sorted | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8

Write-Host ("Scored {0} nominations -> {1}" -f $sorted.Count, $OutPath)
Write-Host ''
$sorted | Select-Object -First 10 |
    Format-Table -AutoSize host, slot, game, complexity, bgg_rating, score, basis, collection, plays, want_to_play, want_to_buy

$flagged = @($sorted | Where-Object { $_.want_to_play -or $_.want_to_buy })
if ($flagged.Count -gt 0) {
    Write-Host ''
    Write-Host '=== on your BGG want-to-play / want-to-buy lists ==='
    $flagged | Format-Table -AutoSize game, host, slot, score, basis, collection, plays, want_to_play, want_to_buy
}
