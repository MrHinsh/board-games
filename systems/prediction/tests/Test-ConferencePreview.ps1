[CmdletBinding()]
param([string]$FixtureRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../conference-previews/ConferencePreview.ps1')

$validWithKnownDefect = '[{"itemid":"1","objectid":"42","geekitem":{"item":{"dynamicinfo":}}}]'
$parsed = @(ConvertFrom-BggPreviewJson -Json $validWithKnownDefect)
if ($parsed.Count -ne 1 -or $null -ne $parsed[0].geekitem.item.dynamicinfo) {
    throw 'Known BGG empty dynamicinfo defect was not repaired narrowly.'
}
$invalidRejected = $false
try { [void](ConvertFrom-BggPreviewJson -Json '[{"other":}]') } catch { $invalidRejected = $true }
if (-not $invalidRejected) { throw 'Unrelated malformed preview JSON must not be silently repaired.' }

$item = [pscustomobject]@{
    itemid = '7'; objectid = '99'; availability_status = 'forsale'; location = '3-A100'
    reactions = [pscustomobject]@{ thumbs = 12 }
    version = [pscustomobject]@{ item = [pscustomobject]@{ name = 'English edition'; objectid = '555' } }
    geekitem = [pscustomobject]@{ item = [pscustomobject]@{
        subtypes = @('boardgame'); yearpublished = '2026'; minplayers = '1'; maxplayers = '4'
        minplaytime = '60'; maxplaytime = '120'; primaryname = [pscustomobject]@{ name = 'Fixture Game' }
        links = [pscustomobject]@{
            boardgamedesigner = @([pscustomobject]@{ name = 'Designer One' })
            boardgamemechanic = @([pscustomobject]@{ name = 'Worker Placement' })
            boardgamecategory = @([pscustomobject]@{ name = 'Science Fiction' })
        }
    } }
}
$candidate = ConvertTo-ConferenceCandidate -Item $item -PreviewId 93 -PreviewTitle 'Fixture Preview'
if ($candidate.bgg_id -ne 99 -or $candidate.name -ne 'Fixture Game' -or $candidate.is_expansion) { throw 'Candidate normalization failed.' }
if ($candidate.designers[0] -ne 'Designer One' -or $candidate.edition_bgg_id -ne 555) { throw 'Candidate linked data normalization failed.' }

$canonical = @(
    [pscustomobject]@{ bgg_id = 10; reimplements = @(20); reimplemented_by = @() },
    [pscustomobject]@{ bgg_id = 30; reimplements = @(); reimplemented_by = @() }
)
$explicit = @([pscustomobject]@{ primary_bgg_id = 20; linked_bgg_ids = @(40) })
$equivalence = Get-ConferenceEquivalenceIndex -CanonicalGames $canonical -ExplicitEquivalences $explicit
if ($equivalence[10] -ne $equivalence[40]) { throw 'Transitive reimplementation and explicit edition equivalence was not collapsed.' }
if ($equivalence[10] -eq $equivalence[30]) { throw 'Unrelated games were collapsed together.' }

$rated = @(
    [pscustomobject]@{ rating = 9.0; mechanics = @('Worker Placement') },
    [pscustomobject]@{ rating = 7.0; mechanics = @('Drafting') }
)
$affinity = Get-ShrunkAffinityScore -CandidateValues @('Worker Placement') -RatedGames $rated -ValueSelector { param($g) $g.mechanics } -ShrinkK 1
if ([math]::Abs($affinity - 8.5) -gt 0.001) { throw "Unexpected shrunk affinity score: $affinity" }
if ((Get-ConferenceRecommendationBand -Score 8.1 -Confidence low -IsExpansion:$false -OwnershipStatus new) -ne 'Worth a demo') { throw 'Low-confidence recommendation cap failed.' }
if ((Get-ConferenceRecommendationBand -Score 8.1 -Confidence medium -IsExpansion:$false -OwnershipStatus new) -ne 'Must investigate') { throw 'Recommendation band threshold failed.' }
if ((Get-ConferenceRecommendationBand -Score 9 -Confidence high -IsExpansion:$true -OwnershipStatus new) -ne 'Expansion') { throw 'Expansion exclusion failed.' }
if ((Get-ConferencePlayTimeLabel -Minimum 90 -Maximum 0) -ne '90 min') { throw 'Incomplete play-time range was not normalized.' }

# Exercise the complete scorer without network access. This guards the rules
# most likely to regress when new candidate sources or ownership states appear.
$integration = Join-Path $FixtureRoot 'conference-scoring'
New-Item -ItemType Directory -Path $integration -Force | Out-Null
$canonicalRows = [System.Collections.Generic.List[object]]::new()
foreach ($i in 1..60) {
    $canonicalRows.Add([pscustomobject]@{
        bgg_id = $i; name = "Training $i"; rating = 6.0 + (($i % 7) * 0.5)
        complexity = 1.0 + (($i % 4) * 0.75); bgg_rating = 6.5 + (($i % 5) * 0.3)
        mechanics = @('Training mechanism'); categories = @('Training theme')
        collection_status = 'Owned'; num_plays = 1; reimplements = @(); reimplemented_by = @()
    })
}
$canonicalRows.Add([pscustomobject]@{
    bgg_id = 900; name = 'Known but eligible'; rating = 0; complexity = 0; bgg_rating = 0
    mechanics = @(); categories = @(); collection_status = 'NotOwned'; num_plays = 0
    want_to_buy = $false; want_to_play = $false; reimplements = @(); reimplemented_by = @()
})
$canonicalRows.Add([pscustomobject]@{
    bgg_id = 904; name = 'Unowned exact replacement'; rating = 0; complexity = 0; bgg_rating = 0
    mechanics = @(); categories = @(); collection_status = 'NotOwned'; num_plays = 0
    reimplements = @(905); reimplemented_by = @()
})
$canonicalRows.Add([pscustomobject]@{
    bgg_id = 905; name = 'Owned equivalent'; rating = 0; complexity = 0; bgg_rating = 0
    mechanics = @(); categories = @(); collection_status = 'Owned'; num_plays = 2
    reimplements = @(); reimplemented_by = @(904)
})
$canonicalPath = Join-Path $integration 'canonical.json'
$canonicalRows | ConvertTo-Json -Depth 8 | Set-Content $canonicalPath
'[]' | Set-Content (Join-Path $integration 'equivalences.json')
'{}' | Set-Content (Join-Path $integration 'designers.json')

$candidateRows = foreach ($id in @(900, 901, 902, 903, 904)) {
    [pscustomobject]@{
        bgg_id = $id; name = "Candidate $id"; year_published = 2026; is_expansion = ($id -eq 902)
        designers = @(); mechanisms = @('Unknown mechanism'); categories = @('Unknown theme')
        min_players = 1; max_players = 4; min_play_time = 90; max_play_time = 0
        thumbs = 10; location = ''; preview_id = 999; preview_title = 'Fixture'
    }
}
$candidatePath = Join-Path $integration 'candidates.json'
[ordered]@{ title = 'Fixture'; source_url = 'https://example.invalid'; candidates = @($candidateRows) } |
    ConvertTo-Json -Depth 8 | Set-Content $candidatePath
$detailRows = foreach ($id in @(900, 901, 902, 903, 904)) {
    [pscustomobject]@{
        id = $id; designer = ''; mechanics = @('Unknown mechanism'); categories = @('Unknown theme')
        complexity = $(if ($id -eq 901) { 0 } else { 3.0 }); bgg_rating = $(if ($id -eq 901) { 0 } else { 8.0 })
        num_ratings = 1500; reimplements = @(); reimplemented_by = @()
    }
}
$detailsPath = Join-Path $integration 'details.json'
$detailRows | ConvertTo-Json -Depth 8 | Set-Content $detailsPath
$rankedPath = Join-Path $integration 'ranked.csv'
& (Join-Path $PSScriptRoot '../conference-previews/Score-ConferencePreview.ps1') `
    -CandidatesPath $candidatePath -OutPath $rankedPath -CanonicalPath $canonicalPath `
    -EquivalencesPath (Join-Path $integration 'equivalences.json') `
    -DesignerIndexPath (Join-Path $integration 'designers.json') -DetailsCachePath $detailsPath `
    -RequestDelayMs 0 | Out-Null
$scored = @(Import-Csv $rankedPath)
$known = $scored | Where-Object bgg_id -eq '900'
$missingPrediction = $scored | Where-Object bgg_id -eq '901'
$expansion = $scored | Where-Object bgg_id -eq '902'
$tiePeer = $scored | Where-Object bgg_id -eq '903'
$coveredReplacement = $scored | Where-Object bgg_id -eq '904'
if ($known.ownership -ne 'new' -or [int]$known.rank -lt 1) { throw 'Unowned and unplayed canonical candidate was incorrectly excluded.' }
if ($missingPrediction.rank -ne '0' -or $missingPrediction.overall) { throw 'Candidate without a model prediction must remain unranked.' }
if ($expansion.rank -ne '0' -or $expansion.recommendation -ne 'Expansion') { throw 'Expansion entered the main ranking.' }
if ($known.rank -ne $tiePeer.rank) { throw 'Candidates inside model RMSE did not share a tie group.' }
if ($coveredReplacement.ownership -ne 'owned' -or $coveredReplacement.rank -ne '0') { throw 'Exact unowned row bypassed its owned equivalent.' }
if ($known.play_time -ne '90 min') { throw 'Scorer emitted an invalid play-time range.' }

Write-Host 'Prediction: conference preview normalization, equivalence, scoring, uncertainty, and ownership rules passed.'
