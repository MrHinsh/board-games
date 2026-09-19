<#
.SYNOPSIS
    Score normalized GeekPreview candidates with the existing taste model.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidatesPath,
    [Parameter(Mandatory = $true)][string]$OutPath,
    [string]$ReportPath,
    [string]$CanonicalPath = '.\data\working\canonical\games.json',
    [string]$EquivalencesPath = '.\data\working\canonical\equivalent-games.json',
    [string]$DesignerIndexPath = '.\data\working\nominations\designer-index.json',
    [string]$DetailsCachePath = '.\data\working\conferences\bgg-details.json',
    [string]$Endpoint = 'http://localhost:8080/mcp',
    [int]$RequestDelayMs = 2000,
    [switch]$RefreshDetails
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ConferencePreview.ps1')
. (Join-Path $PSScriptRoot '../model/BggTasteModel.ps1')
. (Join-Path $PSScriptRoot '../../bgg-integration/provider/Invoke-BggMcp.ps1')

foreach ($path in @($CandidatesPath, $CanonicalPath, $DesignerIndexPath)) {
    if (-not (Test-Path $path)) { throw "Required input not found: $path" }
}
$preview = Get-Content -Path $CandidatesPath -Raw | ConvertFrom-Json -Depth 30
$candidates = @($preview.candidates)
$canonical = @(Get-Content -Path $CanonicalPath -Raw | ConvertFrom-Json -Depth 30)
$explicitEquivalences = @()
if (Test-Path $EquivalencesPath) { $explicitEquivalences = @(Get-Content -Path $EquivalencesPath -Raw | ConvertFrom-Json -Depth 10) }
$designerJson = Get-Content -Path $DesignerIndexPath -Raw | ConvertFrom-Json -Depth 10
$designerById = @{}
foreach ($p in $designerJson.PSObject.Properties) { $designerById[[int]$p.Name] = @($p.Value) }

$train = @($canonical | Where-Object {
    [double]$_.rating -gt 0 -and [double]$_.complexity -gt 0 -and [double]$_.bgg_rating -gt 0
})
if ($train.Count -lt 50) { throw "Only $($train.Count) usable training rows; refusing to fit." }
$model = New-BggTasteModel -Games $train -DesignerById $designerById -FeatureSet compact -Folds 5
$personalMean = [double](($train | Measure-Object -Property rating -Average).Average)

$profileGames = foreach ($game in $train) {
    $id = [int]$game.bgg_id
    [pscustomobject]@{
        bgg_id = $id
        rating = [double]$game.rating
        num_plays = [int]$game.num_plays
        complexity = [double]$game.complexity
        max_play_time = 0
        mechanics = @($game.mechanics)
        categories = @($game.categories)
        designers = $(if ($designerById.ContainsKey($id)) { @($designerById[$id]) } else { @() })
    }
}

$detailsById = @{}
if ((Test-Path $DetailsCachePath) -and -not $RefreshDetails.IsPresent) {
    foreach ($detail in @(Get-Content -Path $DetailsCachePath -Raw | ConvertFrom-Json -Depth 30)) {
        $detailsById[[int]$detail.id] = $detail
    }
}
$missingIds = @($candidates | ForEach-Object { [int]$_.bgg_id } | Where-Object { -not $detailsById.ContainsKey($_) } | Sort-Object -Unique)
for ($offset = 0; $offset -lt $missingIds.Count; $offset += 20) {
    $last = [Math]::Min($offset + 19, $missingIds.Count - 1)
    $batch = @($missingIds[$offset..$last])
    $response = @(Invoke-BggMcpTool -ToolName 'bgg-details' -Arguments @{ ids = $batch } -Endpoint $Endpoint)
    foreach ($detail in @($response | Where-Object { $_ -and $_.PSObject.Properties['id'] })) {
        $detailsById[[int]$detail.id] = $detail
    }
    if ($RequestDelayMs -gt 0 -and $last -lt ($missingIds.Count - 1)) { Start-Sleep -Milliseconds $RequestDelayMs }
}
if ($detailsById.Count -gt 0) {
    $cacheDir = Split-Path -Parent $DetailsCachePath
    if ($cacheDir -and -not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
    @($detailsById.Values | Sort-Object { [int]$_.id }) | ConvertTo-Json -Depth 20 | Set-Content -Path $DetailsCachePath -Encoding UTF8
}

$detailRelationshipRows = @($detailsById.Values | ForEach-Object {
    [pscustomobject]@{
        bgg_id = [int]$_.id
        reimplements = @($_.reimplements)
        reimplemented_by = @($_.reimplemented_by)
    }
})
$equivalenceIndex = Get-ConferenceEquivalenceIndex -CanonicalGames @($canonical + $detailRelationshipRows) -ExplicitEquivalences $explicitEquivalences
$canonicalById = @{}; foreach ($game in $canonical) { $canonicalById[[int]$game.bgg_id] = $game }
$canonicalByRoot = @{}
foreach ($game in $canonical) {
    $id = [int]$game.bgg_id
    $root = $(if ($equivalenceIndex.ContainsKey($id)) { [int]$equivalenceIndex[$id] } else { $id })
    if (-not $canonicalByRoot.ContainsKey($root)) { $canonicalByRoot[$root] = [System.Collections.Generic.List[object]]::new() }
    $canonicalByRoot[$root].Add($game)
}

$rows = foreach ($candidate in $candidates) {
    $id = [int]$candidate.bgg_id
    $detail = $(if ($detailsById.ContainsKey($id)) { $detailsById[$id] } else { $null })
    if ($detail) {
        $designers = @(([string]$detail.designer -split ',\s*') | Where-Object { $_ })
        $mechanisms = @($detail.mechanics | Where-Object { $_ })
        $categories = @($detail.categories | Where-Object { $_ })
    } else {
        $designers = @($candidate.designers | Where-Object { $_ })
        $mechanisms = @($candidate.mechanisms | Where-Object { $_ })
        $categories = @($candidate.categories | Where-Object { $_ })
    }

    $matches = @()
    $root = $(if ($equivalenceIndex.ContainsKey($id)) { [int]$equivalenceIndex[$id] } else { $id })
    if ($canonicalByRoot.ContainsKey($root)) { $matches = @($canonicalByRoot[$root]) }
    elseif ($canonicalById.ContainsKey($id)) { $matches = @($canonicalById[$id]) }
    $owned = @($matches | Where-Object { $_.collection_status -in @('Owned', 'OwnedToExit') }).Count -gt 0
    $played = @($matches | Where-Object { [int]$_.num_plays -gt 0 }).Count -gt 0
    $ownership = $(if ($owned) { 'owned' } elseif ($played) { 'played-not-owned' } else { 'new' })
    $matchedIds = @($matches | ForEach-Object { [int]$_.bgg_id } | Sort-Object -Unique)

    $candidateForModel = [pscustomobject]@{
        bgg_id = $id
        complexity = $(if ($detail) { [double]$detail.complexity } else { 0.0 })
        bgg_rating = $(if ($detail) { [double]$detail.bgg_rating } else { 0.0 })
        categories = $categories
        mechanics = $mechanisms
        max_play_time = $(if ([int]$candidate.max_play_time -gt 0) { [int]$candidate.max_play_time } else { [int]$candidate.min_play_time })
    }
    $predicted = $null; $designerAdjustment = 0.0; $designerHits = @()
    if ($candidateForModel.complexity -gt 0 -and $candidateForModel.bgg_rating -gt 0) {
        $prediction = Get-BggTastePrediction -Model $model -Game $candidateForModel -Designers @($designers)
        $predicted = [double]$prediction.Prediction
        $designerAdjustment = [double]$prediction.DesignerAdjustment
        $designerHits = @($prediction.DesignerHits)
    }

    $designerScore = Get-ShrunkAffinityScore -CandidateValues $designers -RatedGames $profileGames -ValueSelector { param($g) $g.designers }
    $mechanismScore = Get-ShrunkAffinityScore -CandidateValues $mechanisms -RatedGames $profileGames -ValueSelector { param($g) $g.mechanics }
    $themeScore = Get-ShrunkAffinityScore -CandidateValues $categories -RatedGames $profileGames -ValueSelector { param($g) $g.categories }
    $typeScore = Get-TypeAffinityScore -Candidate $candidateForModel -RatedGames $profileGames
    $designerEvidence = @(Get-ConferenceAffinityEvidence -CandidateValues $designers -RatedGames $profileGames -ValueSelector { param($g) $g.designers })
    $mechanismEvidence = @(Get-ConferenceAffinityEvidence -CandidateValues $mechanisms -RatedGames $profileGames -ValueSelector { param($g) $g.mechanics })
    $themeEvidence = @(Get-ConferenceAffinityEvidence -CandidateValues $categories -RatedGames $profileGames -ValueSelector { param($g) $g.categories })
    $designerReason = Format-ConferenceEvidence -Evidence $designerEvidence -Take 2 -IncludePlays
    $mechanismReason = Format-ConferenceEvidence -Evidence $mechanismEvidence -Take 3
    $themeReason = Format-ConferenceEvidence -Evidence $themeEvidence -Take 3
    $typeSampleSize = @($profileGames | Where-Object { [double]$_.complexity -gt 0 }).Count
    $typeReason = $(if ($null -ne $typeScore) {
        "Complexity $([math]::Round([double]$candidateForModel.complexity, 1)); a complexity-weighted comparison across $typeSampleSize rated games yields $([math]::Round([double]$typeScore, 1))."
    } else { '' })

    # Keep the agreed weights fixed. Missing explanatory affinities are neutral at
    # the operator's mean; a missing model prediction makes the row unrankable.
    $overall = $null
    if ($null -ne $predicted) {
        $overall = (0.50 * $predicted) +
            (0.20 * $(if ($null -ne $designerScore) { $designerScore } else { $personalMean })) +
            (0.125 * $(if ($null -ne $mechanismScore) { $mechanismScore } else { $personalMean })) +
            (0.125 * $(if ($null -ne $typeScore) { $typeScore } else { $personalMean })) +
            (0.05 * $(if ($null -ne $themeScore) { $themeScore } else { $personalMean }))
    }
    $numRatings = $(if ($detail) { [int]$detail.num_ratings } else { 0 })
    $confidence = $(
        if ($null -eq $predicted -or $numRatings -lt 10) { 'insufficient' }
        elseif ($numRatings -lt 300) { 'low' }
        elseif ($numRatings -lt 1000) { 'medium' }
        else { 'high' }
    )
    $band = Get-ConferenceRecommendationBand -Score $(if ($null -ne $overall) { $overall } else { 0.0 }) -Confidence $confidence -IsExpansion ([bool]$candidate.is_expansion) -OwnershipStatus $ownership

    $positiveDesignerEvidence = @($designerEvidence | Where-Object { [double]$_.lift -gt 0 })
    $positiveMechanismEvidence = @($mechanismEvidence | Where-Object { [double]$_.lift -gt 0 })
    $positiveThemeEvidence = @($themeEvidence | Where-Object { [double]$_.lift -gt 0 })
    $negativeDesignerEvidence = @($designerEvidence | Where-Object { [double]$_.lift -le 0 } | Sort-Object lift)
    $negativeMechanismEvidence = @($mechanismEvidence | Where-Object { [double]$_.lift -le 0 } | Sort-Object lift)
    $negativeThemeEvidence = @($themeEvidence | Where-Object { [double]$_.lift -le 0 } | Sort-Object lift)
    $positiveDesignerReason = Format-ConferenceEvidence -Evidence $positiveDesignerEvidence -Take 2 -IncludePlays
    $positiveMechanismReason = Format-ConferenceEvidence -Evidence $positiveMechanismEvidence -Take 3
    $positiveThemeReason = Format-ConferenceEvidence -Evidence $positiveThemeEvidence -Take 3
    $negativeDesignerReason = Format-ConferenceEvidence -Evidence $negativeDesignerEvidence -Take 2 -IncludePlays
    $negativeMechanismReason = Format-ConferenceEvidence -Evidence $negativeMechanismEvidence -Take 2
    $negativeThemeReason = Format-ConferenceEvidence -Evidence $negativeThemeEvidence -Take 2
    $sciFiSignal = ((@($categories) -join ' ') -match 'Science Fiction|Space Exploration')
    $positiveReasons = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $predicted) { $positiveReasons.Add("Compact model predicts $([math]::Round($predicted, 1))/10 using BGG rating $([math]::Round([double]$candidateForModel.bgg_rating, 1)), complexity $([math]::Round([double]$candidateForModel.complexity, 1)), science-fiction signal $(if ($sciFiSignal) { 'on' } else { 'off' }), and any available designer adjustment.") }
    if ($positiveDesignerReason) { $positiveReasons.Add("Positive designer evidence — $positiveDesignerReason.") }
    if ($positiveMechanismReason) { $positiveReasons.Add("Positive mechanism evidence — $positiveMechanismReason.") }
    if ($positiveThemeReason) { $positiveReasons.Add("Positive theme evidence — $positiveThemeReason.") }
    if ($typeReason -and [double]$typeScore -gt $personalMean) { $positiveReasons.Add("Positive type evidence — $typeReason") }
    if ($positiveReasons.Count -eq 0) { $positiveReasons.Add('There is not enough overlap with your rated history to explain a personal fit yet.') }

    $cautions = [System.Collections.Generic.List[string]]::new()
    if ([bool]$candidate.is_expansion) { $cautions.Add('Expansion: excluded from the base-game ranking.') }
    if ($ownership -eq 'owned') { $cautions.Add("Already covered by owned game ID(s) $($matchedIds -join ', ').") }
    elseif ($ownership -eq 'played-not-owned') { $cautions.Add("Already played through game ID(s) $($matchedIds -join ', ').") }
    if ($null -eq $predicted) { $cautions.Add('No usable BGG rating or complexity, so the compact taste model cannot rank it.') }
    elseif ($confidence -eq 'insufficient') { $cautions.Add("Only $numRatings BGG ratings; the prerelease average is highly unstable.") }
    elseif ($confidence -eq 'low') { $cautions.Add("Only $numRatings BGG ratings; treat the current average as provisional.") }
    elseif ($confidence -eq 'medium') { $cautions.Add("$numRatings BGG ratings provide moderate evidence, but the average may still move.") }
    if ($designers.Count -eq 0) { $cautions.Add('BGG lists no credited designer metadata.') }
    elseif ($designerEvidence.Count -eq 0) { $cautions.Add('You have no rated history for the credited designer(s).') }
    if ($mechanisms.Count -eq 0) { $cautions.Add('BGG lists no mechanism metadata.') }
    elseif ($mechanismEvidence.Count -eq 0) { $cautions.Add('Its mechanisms have no direct evidence in your rated history.') }
    if ($categories.Count -eq 0) { $cautions.Add('BGG lists no category/theme metadata.') }
    elseif ($themeEvidence.Count -eq 0) { $cautions.Add('Its themes have no direct evidence in your rated history.') }
    if ($negativeDesignerReason) { $cautions.Add("Lower-rated designer evidence — $negativeDesignerReason.") }
    if ($negativeMechanismReason) { $cautions.Add("Lower-rated mechanism evidence — $negativeMechanismReason.") }
    if ($negativeThemeReason) { $cautions.Add("Lower-rated theme evidence — $negativeThemeReason.") }
    if ($typeReason -and [double]$typeScore -le $personalMean) { $cautions.Add("Lower-rated type evidence — $typeReason") }
    $cautions.Add("The model CV RMSE is $([math]::Round($model.CvRmse, 1)); smaller score gaps are not meaningful.")

    [pscustomobject][ordered]@{
        rank = 0
        game = [string]$candidate.name
        bgg_id = $id
        year = [int]$candidate.year_published
        recommendation = $band
        overall = $(if ($null -ne $overall) { [math]::Round($overall, 2) } else { $null })
        predicted = $(if ($null -ne $predicted) { [math]::Round($predicted, 2) } else { $null })
        designer = $(if ($null -ne $designerScore) { [math]::Round($designerScore, 2) } else { $null })
        mechanism = $(if ($null -ne $mechanismScore) { [math]::Round($mechanismScore, 2) } else { $null })
        theme = $(if ($null -ne $themeScore) { [math]::Round($themeScore, 2) } else { $null })
        type = $(if ($null -ne $typeScore) { [math]::Round($typeScore, 2) } else { $null })
        confidence = $confidence
        num_ratings = $numRatings
        complexity = [math]::Round([double]$candidateForModel.complexity, 2)
        designers = ($designers -join ' / ')
        designer_hits = ($designerHits -join ' / ')
        designer_adjustment = [math]::Round($designerAdjustment, 2)
        ownership = $ownership
        matched_bgg_ids = ($matchedIds -join ' / ')
        expansion = [bool]$candidate.is_expansion
        thumbs = [int]$candidate.thumbs
        players = Get-ConferencePlayerLabel -Minimum ([int]$candidate.min_players) -Maximum ([int]$candidate.max_players)
        play_time = Get-ConferencePlayTimeLabel -Minimum ([int]$candidate.min_play_time) -Maximum ([int]$candidate.max_play_time)
        location = [string]$candidate.location
        why_you_may_like_it = ($positiveReasons -join ' ')
        designer_evidence = $designerReason
        mechanism_evidence = $mechanismReason
        theme_evidence = $themeReason
        type_evidence = $typeReason
        cautions = ($cautions -join ' ')
    }
}

$sorted = @($rows | Sort-Object -Property `
    @{ Expression = { $_.recommendation -eq 'Already covered' -or $_.recommendation -eq 'Expansion' }; Descending = $false },
    @{ Expression = { $null -ne $_.overall }; Descending = $true },
    @{ Expression = { [double]$_.overall }; Descending = $true },
    @{ Expression = { [int]$_.thumbs }; Descending = $true })
$rankedCandidates = @($sorted | Where-Object { $_.ownership -eq 'new' -and -not $_.expansion -and $null -ne $_.overall })
$tieGroup = 0; $previousScore = $null
foreach ($row in $rankedCandidates) {
    # Start a new component only across a real gap larger than RMSE. Comparing
    # adjacent sorted scores avoids claiming two nearly identical boundary rows
    # belong to different precision groups.
    if ($null -eq $previousScore -or ($previousScore - [double]$row.overall) -gt [double]$model.CvRmse) {
        $tieGroup++
    }
    $row.rank = $tieGroup
    $previousScore = [double]$row.overall
}
$outDir = Split-Path -Parent $OutPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sorted | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8

if ($ReportPath) {
    $reportDir = Split-Path -Parent $ReportPath
    if ($reportDir -and -not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
    $top = @($rankedCandidates | Select-Object -First 30)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# $($preview.title) recommendations")
    $lines.Add('')
    $lines.Add("Generated $((Get-Date).ToString('yyyy-MM-dd')). Source: $($preview.source_url).")
    $lines.Add('')
    $lines.Add("Taste-model CV RMSE: $([math]::Round($model.CvRmse, 3)). Differences smaller than about $([math]::Round($model.CvRmse, 1)) points are noise. Mechanism, theme and type scores are shrunk similarity explanations, not separately validated predictors.")
    $lines.Add('')
    $lines.Add('| Tie group | Game | Band | Overall | Predicted | Designer | Mechanism | Theme | Type | Confidence | BGG ratings |')
    $lines.Add('| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |')
    foreach ($row in $top) {
        $lines.Add("| $($row.rank) | [$($row.game)](https://boardgamegeek.com/boardgame/$($row.bgg_id)) | $($row.recommendation) | $($row.overall) | $($row.predicted) | $($row.designer) | $($row.mechanism) | $($row.theme) | $($row.type) | $($row.confidence) | $($row.num_ratings) |")
    }
    $lines.Add('')
    $lines.Add('## Detailed reasons')
    foreach ($row in $top) {
        $lines.Add('')
        $lines.Add("### [$($row.game)](https://boardgamegeek.com/boardgame/$($row.bgg_id))")
        $lines.Add('')
        $lines.Add("**Recommendation:** $($row.recommendation) · **Overall:** $($row.overall) · **Confidence:** $($row.confidence) · **Profile:** complexity $($row.complexity), $($row.players) players, $($row.play_time).")
        $lines.Add('')
        $lines.Add("**Why it may fit:** $($row.why_you_may_like_it)")
        $lines.Add('')
        $lines.Add("**Cautions:** $($row.cautions)")
    }
    $covered = @($sorted | Where-Object { $_.ownership -ne 'new' }).Count
    $expansions = @($sorted | Where-Object { $_.expansion }).Count
    $lines.Add('')
    $lines.Add("Excluded from the main ranking: $covered already covered by the collection/play history; $expansions expansions.")
    $lines | Set-Content -Path $ReportPath -Encoding UTF8
}

Write-Host ("Scored {0} conference games; {1} rankable new base-game candidates in {2} tie groups -> {3}" -f $sorted.Count, $rankedCandidates.Count, $tieGroup, $OutPath)
Write-Host ("CV RMSE: {0}; treat smaller score gaps as noise." -f [math]::Round($model.CvRmse, 3))
$sorted | Where-Object { $_.ownership -eq 'new' -and -not $_.expansion } | Select-Object -First 10 |
    Format-Table -AutoSize rank, game, recommendation, overall, predicted, designer, confidence, num_ratings
